import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../theme.dart';

/// Kopira tekst u sistemski clipboard. Vraća true ako je uspelo.
Future<bool> copyToClipboard(String text) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    return true;
  } catch (_) {
    return false;
  }
}

/// Renderuje IPS QR kod kao PNG (beli okvir, kao QR kartica u aplikaciji)
/// i otvara sistemski share dijalog.
Future<void> shareQrCode(
  String ipsString,
  String title,
  String description,
) async {
  const qrSize = 560.0;
  const padding = 48.0;
  const total = qrSize + padding * 2;

  final painter = QrPainter(
    data: ipsString,
    version: QrVersions.auto,
    errorCorrectionLevel: QrErrorCorrectLevel.M,
    eyeStyle: const QrEyeStyle(
      eyeShape: QrEyeShape.square,
      color: AppColors.qrFg,
    ),
    dataModuleStyle: const QrDataModuleStyle(
      dataModuleShape: QrDataModuleShape.square,
      color: AppColors.qrFg,
    ),
    gapless: true,
  );

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, total, total),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  canvas.translate(padding, padding);
  painter.paint(canvas, const ui.Size(qrSize, qrSize));

  final image = await recorder.endRecording().toImage(
    total.toInt(),
    total.toInt(),
  );
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  if (byteData == null) return;

  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/ips-qr.png');
  await file.writeAsBytes(byteData.buffer.asUint8List());

  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'image/png')],
      subject: title,
      text: description,
    ),
  );
}

/// Upisuje [content] u privremeni .json fajl i otvara sistemski share
/// dijalog — koristi se za izvoz sačuvanih IPS kodova radi prenosa na
/// drugi uređaj (nema sopstvenog servera za sinhronizaciju).
Future<void> shareJsonBackup(
  String content,
  String fileName,
  String subject,
  String text,
) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsString(content);

  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'application/json')],
      subject: subject,
      text: text,
    ),
  );
}
