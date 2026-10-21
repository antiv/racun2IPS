import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../models/invoice_data.dart';
import '../utils/ips.dart';

/// Lokalna detekcija postojećeg NBS IPS QR koda na slici računa pomoću ML Kit-a.
///
/// Ako račun već sadrži odštampan NBS IPS QR kod (K:PR ili K:EK), podaci se
/// izvlače direktno za <100ms bez pokretanja OCR-a ili poziva ka Gemini AI-ju.
/// QR kodovi koji nisu NBS IPS format (npr. URL fiskalnog računa) se ignorišu.
class QrScannerService {
  /// Pokušava da pronađe i parsira NBS IPS QR kod sa prosleđenih bajtova slike.
  Future<InvoiceData?> tryExtractIpsFromBytes(Uint8List imageBytes) async {
    File? tempFile;
    try {
      final dir = await getTemporaryDirectory();
      tempFile = File(
        '${dir.path}/ips_qr_scan_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await tempFile.writeAsBytes(imageBytes, flush: true);
      return await tryExtractIpsFromFile(tempFile.path);
    } catch (e) {
      debugPrint('QrScannerService error: $e');
      return null;
    } finally {
      try {
        if (tempFile != null && await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
    }
  }

  /// Pokušava da pronađe i parsira NBS IPS QR kod iz fajla slike na putanji [filePath].
  Future<InvoiceData?> tryExtractIpsFromFile(String filePath) async {
    // 1. Brzi prolaz nad originalnim fajlom.
    final direct = await _scanFile(filePath);
    if (direct != null) return direct;

    // 2. Ako brzi prolaz nije pronašao QR kod (čest slučaj kod fotografija visoke
    // rezolucije gde ML Kit smanjuje sliku i gubi detalje gustog IPS QR koda),
    // normalizuj EXIF orijentaciju, optimizuj rezoluciju i proveri ključne regije.
    final fallbackFiles = <File>[];
    try {
      final bytes = await File(filePath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      final oriented = img.bakeOrientation(decoded);
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().microsecondsSinceEpoch;

      // 2a. Optimizovana rezolucija (max 1600px po dužoj strani - idealno za ML Kit).
      final maxDim =
          oriented.width > oriented.height ? oriented.width : oriented.height;
      if (maxDim > 1600) {
        final scaled = img.copyResize(
          oriented,
          width: oriented.width > oriented.height ? 1600 : null,
          height: oriented.height >= oriented.width ? 1600 : null,
          interpolation: img.Interpolation.linear,
        );
        final scaledFile = File('${dir.path}/ips_qr_scaled_$stamp.jpg');
        await scaledFile.writeAsBytes(
          img.encodeJpg(scaled, quality: 90),
          flush: true,
        );
        fallbackFiles.add(scaledFile);

        final scaledResult = await _scanFile(scaledFile.path);
        if (scaledResult != null) return scaledResult;
      }

      // 2b. Segmenti računa (uplatnica / leva regija gde EPS i Infostan stavljaju QR kod).
      // Na celom A4 papiru QR kod zauzima samo mali procenat površine; u isečku je dominantan.
      final w = oriented.width;
      final h = oriented.height;

      // Leva polovina / sredina (tipično mesto za QR na EPS i većini računa)
      if (w > 200 && h > 200) {
        final leftRegion = img.copyCrop(
          oriented,
          x: 0,
          y: (h * 0.15).toInt(),
          width: (w * 0.7).toInt(),
          height: (h * 0.7).toInt(),
        );
        final leftFile = File('${dir.path}/ips_qr_crop_left_$stamp.jpg');
        await leftFile.writeAsBytes(
          img.encodeJpg(leftRegion, quality: 90),
          flush: true,
        );
        fallbackFiles.add(leftFile);

        final leftResult = await _scanFile(leftFile.path);
        if (leftResult != null) return leftResult;

        // Donja polovina (uplatnica)
        final bottomRegion = img.copyCrop(
          oriented,
          x: 0,
          y: (h * 0.35).toInt(),
          width: w,
          height: (h * 0.65).toInt(),
        );
        final bottomFile = File('${dir.path}/ips_qr_crop_bottom_$stamp.jpg');
        await bottomFile.writeAsBytes(
          img.encodeJpg(bottomRegion, quality: 90),
          flush: true,
        );
        fallbackFiles.add(bottomFile);

        final bottomResult = await _scanFile(bottomFile.path);
        if (bottomResult != null) return bottomResult;

        // Desna polovina / donja desna regija (Yettel, A1, MTS)
        final rightRegion = img.copyCrop(
          oriented,
          x: (w * 0.35).toInt(),
          y: (h * 0.35).toInt(),
          width: (w * 0.65).toInt(),
          height: (h * 0.65).toInt(),
        );
        final rightFile = File('${dir.path}/ips_qr_crop_right_$stamp.jpg');
        await rightFile.writeAsBytes(
          img.encodeJpg(rightRegion, quality: 90),
          flush: true,
        );
        fallbackFiles.add(rightFile);

        final rightResult = await _scanFile(rightFile.path);
        if (rightResult != null) return rightResult;
      }

      return null;
    } catch (e) {
      debugPrint('QrScannerService fallback scanning error: $e');
      return null;
    } finally {
      for (final f in fallbackFiles) {
        try {
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
  }

  Future<InvoiceData?> _scanFile(String path) async {
    final scanner = BarcodeScanner(formats: [BarcodeFormat.qrCode]);
    try {
      final inputImage = InputImage.fromFilePath(path);
      final barcodes = await scanner.processImage(inputImage);
      for (final barcode in barcodes) {
        final raw = barcode.rawValue;
        if (raw == null || raw.isEmpty) continue;
        final parsed = parseIpsString(raw);
        if (parsed != null && validateAccountNumber(parsed.accountNumber)) {
          return parsed;
        }
      }
      return null;
    } catch (e) {
      debugPrint('QrScannerService _scanFile error on $path: $e');
      return null;
    } finally {
      await scanner.close();
    }
  }
}
