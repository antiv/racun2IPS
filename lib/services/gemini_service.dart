import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../constants/ips.dart';
import '../models/invoice_data.dart';
import '../utils/ips.dart';

/// API ključ se prosleđuje pri build-u: --dart-define-from-file=.env
const _apiKey = String.fromEnvironment('GEMINI_API_KEY');

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
  if (_apiKey.isEmpty) {
    throw Exception('Gemini API key is missing.');
  }

  final dio = Dio();
  final Response<Map<String, dynamic>> response;
  try {
    response = await dio.post<Map<String, dynamic>>(
      'https://generativelanguage.googleapis.com/v1beta/models/$geminiModel:generateContent',
      queryParameters: {'key': _apiKey},
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
    data.accountNumber = parseAccountNumber(data.accountNumber);

    // Srpski računi su uvek PPP (3) + NNNNNNNNNNNNN (13) + KK (2) = 18 cifara.
    // LLM ponekad vrati pogrešan broj cifara — normalizuj srednji deo.
    if (data.accountNumber.length != 18 && data.accountNumber.length >= 5) {
      final acc = data.accountNumber;
      final bankPrefix = acc.substring(0, 3);
      final checkDigits = acc.substring(acc.length - 2);
      final middle = acc.substring(3, acc.length - 2);
      final normalizedMiddle = middle.length <= 13
          ? middle.padLeft(13, '0')
          : middle.substring(middle.length - 13);
      data.accountNumber = '$bankPrefix$normalizedMiddle$checkDigits';
    }
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
