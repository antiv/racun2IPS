import 'dart:convert';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

import '../constants/ips.dart';
import '../models/invoice_data.dart';
import '../utils/ips.dart';

/// API ključevi se prosleđuju pri build-u: --dart-define-from-file=.env
/// Nezavisni ključevi za Android i iOS omogućavaju restrikciju na nivou platforme
/// (Package Name + SHA-1 za Android, Bundle ID za iOS).
const _apiKeyAndroid = String.fromEnvironment('GEMINI_API_KEY_ANDROID');
const _apiKeyIos = String.fromEnvironment('GEMINI_API_KEY_IOS');
const _apiKeyFallback = String.fromEnvironment('GEMINI_API_KEY');

const _appPackageName = 'rs.antonijevic.invoice2ips';
const _channel = MethodChannel('rs.antonijevic.invoice2ips/shared');

String? _cachedAndroidCertSha1;

String get _apiKey {
  if (Platform.isAndroid && _apiKeyAndroid.isNotEmpty) {
    return _apiKeyAndroid;
  }
  if (Platform.isIOS && _apiKeyIos.isNotEmpty) {
    return _apiKeyIos;
  }
  return _apiKeyFallback;
}

const _prompt = '''Extract invoice details for a Serbian NBS IPS payment.
      Look for:
      - Recipient Name (Primalac, max 70 characters)
      - Account Number (Račun primaoca, MUST be EXACTLY 18 digits. Can be dashed like 840-0000711171843-84 or flat like 840000071117184384. Count carefully - always 18 digits total)
      - Amount (Iznos, in RSD)
      - Payment Code (Šifra plaćanja, exactly 3 digits like 289, 189)
      - Purpose of Payment (Svrha uplate, max 35 characters - DO NOT truncate, return full text as-is)
      - Reference Number (Poziv na broj, max 25 characters. MUST include model without spaces. Dash '-' is allowed, EXCEPT for model 97 where dashes are forbidden. If NO model is found, prepend 00.)''';

/// Šalje sliku računa Gemini API-ju i izvlači podatke za plaćanje.
///
/// Obavezna polja koja nedostaju ostaju prazni stringovi, tako da forma
/// prikaže inline validacione greške.
/// Baca [Exception] sa "429"/"Quota exceeded" u poruci kod prekoračenja kvote.
Future<InvoiceData> processInvoice(Uint8List imageBytes) async {
  final apiKey = _apiKey;
  if (apiKey.isEmpty) {
    final keyName = Platform.isAndroid
        ? 'GEMINI_API_KEY_ANDROID (ili GEMINI_API_KEY)'
        : Platform.isIOS
            ? 'GEMINI_API_KEY_IOS (ili GEMINI_API_KEY)'
            : 'GEMINI_API_KEY';
    throw Exception('Gemini API ključ nedostaje ($keyName).');
  }

  // Zaglavlja za zaštitu API ključa po platformi (Google Cloud Application Restrictions):
  // - Android: X-Android-Package i X-Android-Cert (SHA-1 potpis sertifikata)
  // - iOS: X-Ios-Bundle-Identifier
  final headers = <String, String>{};
  if (Platform.isAndroid) {
    headers['X-Android-Package'] = _appPackageName;
    if (_cachedAndroidCertSha1 == null) {
      try {
        _cachedAndroidCertSha1 =
            await _channel.invokeMethod<String>('getAppSignatureSha1');
      } catch (_) {}
    }
    final certSha1 =
        _cachedAndroidCertSha1 ?? '86262C6ACC0D30A1B6B45375D520F8CA5E409794';
    if (certSha1.isNotEmpty) {
      headers['X-Android-Cert'] = certSha1;
    }
  } else if (Platform.isIOS) {
    headers['X-Ios-Bundle-Identifier'] = _appPackageName;
  }

  final dio = Dio();
  final Response<Map<String, dynamic>> response;
  try {
    response = await dio.post<Map<String, dynamic>>(
      'https://generativelanguage.googleapis.com/v1beta/models/$geminiModel:generateContent',
      queryParameters: {'key': apiKey},
      options: Options(headers: headers),
      data: {
        'contents': [
          {
            'parts': [
              {'text': _prompt},
              {
                'inlineData': {
                  'mimeType': _detectMimeType(imageBytes),
                  'data': base64Encode(imageBytes),
                }
              },
            ]
          }
        ],
        'generationConfig': {
          'responseMimeType': 'application/json',
          'responseSchema': {
            'type': 'OBJECT',
            'properties': {
              'recipientName': {'type': 'STRING'},
              'accountNumber': {
                'type': 'STRING',
                'description': 'Account number, e.g. 115-12345-88 or full 18 digits',
              },
              'amount': {'type': 'NUMBER'},
              'paymentCode': {'type': 'STRING'},
              'purpose': {'type': 'STRING'},
              'referenceNumber': {'type': 'STRING'},
            },
            'required': ['recipientName', 'accountNumber', 'amount'],
          },
        },
      },
    );
  } on DioException catch (e) {
    if (e.response?.statusCode == 429) {
      throw Exception('Quota exceeded (429)');
    }
    final data = e.response?.data;
    if (data is Map && data['error'] is Map) {
      final error = data['error'] as Map;
      final message = error['message'] as String? ?? 'Nepoznata greška';
      final status = error['status'] as String? ?? '';
      throw Exception('Gemini API greška ($status): $message');
    }
    rethrow;
  }

  final text = (((response.data?['candidates'] as List?)?.firstOrNull
              as Map<String, dynamic>?)?['content']?['parts'] as List?)
          ?.map((p) => (p as Map<String, dynamic>)['text'] as String? ?? '')
          .join() ??
      '';
  final json = jsonDecode(text.isEmpty ? '{}' : text) as Map<String, dynamic>;

  final data = InvoiceData(
    recipientName: (json['recipientName'] as String?) ?? '',
    accountNumber: (json['accountNumber'] as String?) ?? '',
    amount: (json['amount'] as num?)?.toDouble() ?? 0,
    paymentCode: (json['paymentCode'] as String?) ?? '289',
    purpose: (json['purpose'] as String?) ?? '',
    referenceNumber: (json['referenceNumber'] as String?) ?? '',
  );

  // Gotovinske šifre plaćanja (počinju sa 1) pretvori u bezgotovinske (2).
  if (data.paymentCode.startsWith('1')) {
    data.paymentCode = '2${data.paymentCode.substring(1)}';
  }

  if (data.accountNumber.isNotEmpty) {
    data.accountNumber = normalizeAccountNumber(data.accountNumber);
  }

  if (data.amount.isNaN || data.amount < 0) {
    data.amount = 0;
  }

  return data;
}

/// Određuje MIME tip slike na osnovu potpisa (magic bytes).
String _detectMimeType(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return 'image/jpeg';
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return 'image/png';
  }
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'image/webp';
  }
  return 'image/jpeg';
}
