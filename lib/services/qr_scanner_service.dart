import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
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
    final scanner = BarcodeScanner(formats: [BarcodeFormat.qrCode]);
    try {
      final inputImage = InputImage.fromFilePath(filePath);
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
      debugPrint('QrScannerService processImage error: $e');
      return null;
    } finally {
      await scanner.close();
    }
  }
}
