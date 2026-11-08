import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../models/invoice_data.dart';
import '../utils/ips.dart';

/// Konfiguracija za MATE platformu.
/// Prosleđuje se pri build-u: --dart-define-from-file=.env
const _mateBaseUrlEnv = String.fromEnvironment(
  'MATE_BASE_URL',
  defaultValue: 'https://ai.antonijevic.rs',
);
const _matePatEnv = String.fromEnvironment('MATE_PAT');
const _mateTokenEnv = String.fromEnvironment('MATE_TOKEN');
const _mateAgentNameEnv = String.fromEnvironment(
  'MATE_AGENT_NAME',
  defaultValue: 'invoice2ips_agent',
);

String get _activeMateToken =>
    _matePatEnv.trim().isNotEmpty ? _matePatEnv.trim() : _mateTokenEnv.trim();

String get _activeMateBaseUrl {
  final raw = _mateBaseUrlEnv.trim().isEmpty
      ? 'https://ai.antonijevic.rs'
      : _mateBaseUrlEnv.trim();
  return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
}

String get _activeMateAgent => _mateAgentNameEnv.trim().isEmpty
    ? 'invoice2ips_agent'
    : _mateAgentNameEnv.trim();

const _invoiceJsonSchema = {
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
};

const _prompt = '''Extract invoice details for a Serbian NBS IPS payment.
Look for:
- Recipient Name (Primalac, max 70 characters; transliterate Cyrillic to Latin)
- Account Number (Račun primaoca, MUST be EXACTLY 18 digits. Can be dashed like 840-0000711171843-84 or flat like 840000071117184384. Count carefully - always 18 digits total)
- Amount (Iznos, in RSD; return 0 if the amount box is blank/missing)
- Payment Code (Šifra plaćanja, exactly 3 digits like 289, 189)
- Purpose of Payment (Svrha uplate, max 35 characters - DO NOT truncate, return full text as-is)
- Reference Number (Poziv na broj, max 25 characters. MUST include model without spaces. Dash '-' is allowed, EXCEPT for model 97 where dashes are forbidden. If NO model is found, prepend 00.)''';

/// Šalje sliku (ili PDF) računa MATE AI agentu i izvlači podatke za plaćanje.
///
/// Obavezna polja koja nedostaju ostaju prazni stringovi (ili 0 za iznos),
/// tako da forma prikaže inline validacione greške.
/// Baca [Exception] sa "429"/"Quota exceeded" u poruci kod prekoračenja kvote.
Future<InvoiceData> processInvoice(Uint8List imageBytes) async {
  final mimeType = _detectMimeType(imageBytes);
  final preparedBytes = mimeType.startsWith('image/')
      ? _ensureImageWithinLimit(imageBytes)
      : imageBytes;
  final b64 = base64Encode(preparedBytes);
  final effectiveMime = mimeType.startsWith('image/') &&
          !identical(preparedBytes, imageBytes)
      ? 'image/jpeg'
      : mimeType;

  return _callMate(
    contentBuilder: (sessionPrompt) => [
      {'type': 'text', 'text': sessionPrompt},
      {
        'type': 'image_url',
        'image_url': {'url': 'data:$effectiveMime;base64,$b64'},
      },
    ],
  );
}

/// Šalje neformalan ili nestrukturiran tekst računa/poruke MATE AI agentu
/// (kada lokalni regex parser ne može pouzdano da izvuče sva polja).
Future<InvoiceData> processInvoiceText(String invoiceText) async {
  return _callMate(
    contentBuilder: (sessionPrompt) =>
        '$sessionPrompt\n\nInvoice text:\n$invoiceText',
  );
}

Future<InvoiceData> _callMate({
  required Object Function(String sessionPrompt) contentBuilder,
}) async {
  final token = _activeMateToken;
  if (token.isEmpty) {
    throw Exception(
      'MATE AI servis nije konfigurisan (nedostaje MATE_PAT u .env fajlu).',
    );
  }

  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 35),
      receiveTimeout: const Duration(seconds: 60),
    ),
  );

  final sessionId = 'ips_${DateTime.now().microsecondsSinceEpoch}';
  final sessionPrompt = '''
[session: $sessionId]
$_prompt

OBAVEZAN FORMAT ODGOVORA:
Vrati ISKLJUČIVO validan JSON objekat (bez markdown ```json blokova i bez dodatnog teksta) koji striktno prati sledeću JSON šemu:
${jsonEncode(_invoiceJsonSchema)}
''';

  final Response<Map<String, dynamic>> response;
  try {
    response = await dio.post<Map<String, dynamic>>(
      '$_activeMateBaseUrl/v1/chat/completions',
      options: Options(
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'X-MATE-Conversation-Id': sessionId,
        },
      ),
      data: {
        'model': _activeMateAgent,
        'messages': [
          {
            'role': 'user',
            'content': contentBuilder(sessionPrompt),
          },
        ],
        'stream': false,
      },
    );
  } on DioException catch (e) {
    if (e.response?.statusCode == 429) {
      throw Exception('Quota exceeded (429)');
    }
    final data = e.response?.data;
    if (data is Map) {
      final detail = data['detail'] ??
          (data['error'] is Map ? (data['error'] as Map)['message'] : null) ??
          e.message;
      throw Exception('MATE AI greška (${e.response?.statusCode}): $detail');
    }
    rethrow;
  }

  final choices = response.data?['choices'] as List<dynamic>?;
  final message = (choices != null && choices.isNotEmpty)
      ? choices.first['message'] as Map<String, dynamic>?
      : null;
  final rawText = message?['content'] as String? ?? '';
  final json = _extractJsonMap(rawText) ?? <String, dynamic>{};
  return _mapJsonToInvoiceData(json);
}

Map<String, dynamic>? _extractJsonMap(String raw) {
  var cleaned = raw.trim();
  if (cleaned.isEmpty) return null;
  if (cleaned.startsWith('```')) {
    cleaned = cleaned
        .replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '')
        .replaceFirst(RegExp(r'\s*```$'), '')
        .trim();
  }
  final start = cleaned.indexOf('{');
  final end = cleaned.lastIndexOf('}');
  if (start != -1 && end != -1 && end > start) {
    cleaned = cleaned.substring(start, end + 1);
  }
  final decoded = jsonDecode(cleaned);
  return decoded is Map<String, dynamic> ? decoded : null;
}

InvoiceData _mapJsonToInvoiceData(Map<String, dynamic> json) {
  final rawAmount = json['amount'];
  final parsedAmount = switch (rawAmount) {
    num n => n.toDouble(),
    String s => double.tryParse(s.replaceAll(',', '.').trim()) ?? 0.0,
    _ => 0.0,
  };

  final data = InvoiceData(
    recipientName: (json['recipientName'] as String?)?.trim() ?? '',
    accountNumber: (json['accountNumber'] as String?)?.trim() ?? '',
    amount: parsedAmount,
    paymentCode: (json['paymentCode'] as String?)?.trim() ?? '289',
    purpose: (json['purpose'] as String?)?.trim() ?? '',
    referenceNumber: (json['referenceNumber'] as String?)?.trim() ?? '',
  );

  if (data.paymentCode.isEmpty) {
    data.paymentCode = '289';
  } else if (data.paymentCode.startsWith('1')) {
    // Gotovinske šifre plaćanja (počinju sa 1) pretvori u bezgotovinske (2).
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

/// Osigurava da slika ne prelazi 3.5 MB pre base64 kodiranja (MATE limit je 5 MB).
Uint8List _ensureImageWithinLimit(Uint8List bytes) {
  const maxRawBytes = 3500 * 1024;
  if (bytes.length <= maxRawBytes) return bytes;
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    var processed = img.bakeOrientation(decoded);
    final longest = math.max(processed.width, processed.height);
    if (longest > 2200) {
      final scale = 2200 / longest;
      processed = img.copyResize(
        processed,
        width: (processed.width * scale).round(),
        height: (processed.height * scale).round(),
        interpolation: img.Interpolation.average,
      );
    }
    return Uint8List.fromList(img.encodeJpg(processed, quality: 85));
  } catch (_) {
    return bytes;
  }
}

/// Određuje MIME tip slike ili PDF dokumenta na osnovu potpisa (magic bytes).
String _detectMimeType(Uint8List bytes) {
  if (bytes.length >= 4 &&
      bytes[0] == 0x25 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x44 &&
      bytes[3] == 0x46) {
    return 'application/pdf';
  }
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
