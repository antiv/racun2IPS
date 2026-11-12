import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Kanal ka native sloju (MainActivity na Androidu / AppDelegate na iOS-u):
/// 1. Preuzima sliku, PDF dokument ili tekst podeljen iz druge aplikacije (ACTION_SEND / ACTION_VIEW),
/// 2. Renderuje stranice PDF dokumenta u PNG slike pomoću ugrađenog OS PDF renderer-a,
/// 3. Čita tekstualni sloj PDF dokumenta (PDFKit / pdfbox-android).
const _channel = MethodChannel('rs.antonijevic.invoice2ips/shared');

enum SharedPayloadType { image, pdf, text }

class SharedPayload {
  const SharedPayload({required this.type, this.bytes, this.text});

  final SharedPayloadType type;
  final Uint8List? bytes;
  final String? text;
}

/// Preuzima podeljeni sadržaj (sliku, PDF ili tekst) iz native sloja.
/// Native strana briše podatke nakon čitanja, pa se isti sadržaj ne obrađuje dvaput.
Future<SharedPayload?> getSharedPayload() async {
  try {
    final raw = await _channel.invokeMethod<dynamic>('getSharedPayload');
    if (raw is! Map) return null;
    final typeStr = raw['type']?.toString();
    final bytesRaw = raw['bytes'];
    final Uint8List? bytes = bytesRaw is Uint8List
        ? bytesRaw
        : (bytesRaw is List ? Uint8List.fromList(bytesRaw.cast<int>()) : null);
    final text = raw['text']?.toString();

    switch (typeStr) {
      case 'image':
        if (bytes != null && bytes.isNotEmpty) {
          debugPrint(
            'getSharedPayload: primljena slika (${bytes.length} bajtova)',
          );
          return SharedPayload(type: SharedPayloadType.image, bytes: bytes);
        }
        return null;
      case 'pdf':
        if (bytes != null && bytes.isNotEmpty) {
          debugPrint(
            'getSharedPayload: primljen PDF (${bytes.length} bajtova)',
          );
          return SharedPayload(type: SharedPayloadType.pdf, bytes: bytes);
        }
        return null;
      case 'text':
        if (text != null && text.trim().isNotEmpty) {
          debugPrint(
            'getSharedPayload: primljen tekst (${text.length} karaktera)',
          );
          return SharedPayload(type: SharedPayloadType.text, text: text);
        }
        return null;
      default:
        return null;
    }
  } catch (e, stack) {
    debugPrint('getSharedPayload error: $e\n$stack');
    return null;
  }
}

/// Renderuje stranice PDF dokumenta u listu PNG slika visoke rezolucije
/// koristeći ugrađeni Android PdfRenderer odnosno iOS PDFKit.
Future<List<Uint8List>> renderPdfPages(Uint8List pdfBytes) async {
  try {
    final result = await _channel.invokeMethod<dynamic>('renderPdfPages', {
      'bytes': pdfBytes,
    });
    if (result is! List) return const [];
    final pages = <Uint8List>[];
    for (final item in result) {
      if (item is Uint8List) {
        pages.add(item);
      } else if (item is List) {
        pages.add(Uint8List.fromList(item.cast<int>()));
      }
    }
    debugPrint('renderPdfPages: uspešno renderovano ${pages.length} stranica');
    return pages;
  } catch (e, stack) {
    debugPrint('renderPdfPages error: $e\n$stack');
    return const [];
  }
}

/// Tekstualni sloj PDF-a za iste stranice koje vraća [renderPdfPages]
/// (prazan string za stranicu bez teksta, npr. skeniran PDF).
Future<List<String>> extractPdfText(Uint8List pdfBytes) async {
  try {
    final result = await _channel.invokeMethod<dynamic>('extractPdfText', {
      'bytes': pdfBytes,
    });
    if (result is! List) return const [];
    return result.map((e) => e?.toString() ?? '').toList();
  } catch (e) {
    debugPrint('extractPdfText error: $e');
    return const [];
  }
}

class NativeOcrLine {
  const NativeOcrLine({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;
}

class NativeOcrResult {
  const NativeOcrResult({required this.text, required this.lines});

  final String text;
  final List<NativeOcrLine> lines;
}

/// Pokreće nativni ćirilični/višejezični OCR nad fajlom slike na putanji [filePath]:
/// - na Androidu: Tesseract 4 LSTM sa srpskim ćiriličnim modelom (`srp.traineddata`),
/// - na iOS-u: ugrađeni Apple Vision (`VNRecognizeTextRequest` sa ćirilicom i latinicom).
Future<NativeOcrResult?> recognizeTextNative(String filePath) async {
  try {
    final raw = await _channel.invokeMethod<dynamic>('recognizeTextNative', {
      'path': filePath,
    });
    if (raw is! Map) return null;
    final text = raw['text']?.toString() ?? '';
    final rawLines = raw['lines'];
    final lines = <NativeOcrLine>[];
    if (rawLines is List) {
      for (final item in rawLines) {
        if (item is Map) {
          final lineText = item['text']?.toString().trim() ?? '';
          final left = (item['left'] as num?)?.toDouble() ?? 0.0;
          final top = (item['top'] as num?)?.toDouble() ?? 0.0;
          final right = (item['right'] as num?)?.toDouble() ?? 0.0;
          final bottom = (item['bottom'] as num?)?.toDouble() ?? 0.0;
          if (lineText.isNotEmpty) {
            lines.add(
              NativeOcrLine(
                text: lineText,
                left: left,
                top: top,
                right: right,
                bottom: bottom,
              ),
            );
          }
        }
      }
    }
    if (text.trim().isEmpty && lines.isEmpty) return null;
    return NativeOcrResult(text: text, lines: lines);
  } catch (e) {
    debugPrint('recognizeTextNative error: $e');
    return null;
  }
}
