import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Kanal ka native sloju (MainActivity na Androidu / AppDelegate na iOS-u):
/// 1. Preuzima sliku, PDF dokument ili tekst podeljen iz druge aplikacije (ACTION_SEND / ACTION_VIEW),
/// 2. Renderuje stranice PDF dokumenta u PNG slike pomoću ugrađenog OS PDF renderer-a.
const _channel = MethodChannel('rs.antonijevic.invoice2ips/shared');

enum SharedPayloadType { image, pdf, text }

class SharedPayload {
  const SharedPayload({
    required this.type,
    this.bytes,
    this.text,
  });

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
          debugPrint('getSharedPayload: primljena slika (${bytes.length} bajtova)');
          return SharedPayload(type: SharedPayloadType.image, bytes: bytes);
        }
        return null;
      case 'pdf':
        if (bytes != null && bytes.isNotEmpty) {
          debugPrint('getSharedPayload: primljen PDF (${bytes.length} bajtova)');
          return SharedPayload(type: SharedPayloadType.pdf, bytes: bytes);
        }
        return null;
      case 'text':
        if (text != null && text.trim().isNotEmpty) {
          debugPrint('getSharedPayload: primljen tekst (${text.length} karaktera)');
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
    final result = await _channel.invokeMethod<dynamic>(
      'renderPdfPages',
      {'bytes': pdfBytes},
    );
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
