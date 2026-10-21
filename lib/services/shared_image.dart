import 'package:flutter/services.dart';

/// Kanal ka native sloju (MainActivity na Androidu / AppDelegate na iOS-u):
/// 1. Preuzima sliku, PDF dokument ili tekst podeljen iz druge aplikacije (ACTION_SEND),
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
    final raw = await _channel.invokeMapMethod<String, dynamic>('getSharedPayload');
    if (raw == null) return null;
    final typeStr = raw['type'] as String?;
    final bytes = raw['bytes'] as Uint8List?;
    final text = raw['text'] as String?;

    switch (typeStr) {
      case 'image':
        if (bytes != null && bytes.isNotEmpty) {
          return SharedPayload(type: SharedPayloadType.image, bytes: bytes);
        }
        return null;
      case 'pdf':
        if (bytes != null && bytes.isNotEmpty) {
          return SharedPayload(type: SharedPayloadType.pdf, bytes: bytes);
        }
        return null;
      case 'text':
        if (text != null && text.trim().isNotEmpty) {
          return SharedPayload(type: SharedPayloadType.text, text: text);
        }
        return null;
      default:
        return null;
    }
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}

/// Renderuje stranice PDF dokumenta u listu PNG slika visoke rezolucije
/// koristeći ugrađeni Android PdfRenderer odnosno iOS PDFKit.
Future<List<Uint8List>> renderPdfPages(Uint8List pdfBytes) async {
  try {
    final result = await _channel.invokeListMethod<Uint8List>(
      'renderPdfPages',
      {'bytes': pdfBytes},
    );
    return result ?? const [];
  } on MissingPluginException {
    return const [];
  } on PlatformException {
    return const [];
  }
}
