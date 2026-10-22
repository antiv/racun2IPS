import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

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

  /// Pokušava da pronađe i parsira NBS IPS QR kod iz fajla slike na putanji
  /// [filePath]: brzi prolaz, pa (ako je [deep]) skeniranje isečaka.
  Future<InvoiceData?> tryExtractIpsFromFile(
    String filePath, {
    bool deep = true,
  }) async {
    final direct = await _scanFile(filePath);
    if (direct != null || !deep) return direct;
    return tryExtractIpsFromTiles(filePath);
  }

  /// Sporiji prolaz (nekoliko sekundi na velikoj fotografiji) nad isečcima
  /// slike na putanji [filePath].
  Future<InvoiceData?> tryExtractIpsFromTiles(String filePath) async {
    // IPS QR na računu je često sitan u odnosu na celu stranu (npr. EPS
    // PDF: ~150px na strani od 2000px, ~3px po modulu), pa ga ML Kit ne vidi.
    // Skenira se mreža preklapajućih isečaka, uvećanih kad su mali, tako da
    // QR u isečku bude dominantan i dovoljno krupan.
    final fallbackFiles = <File>[];
    try {
      final bytes = await File(filePath).readAsBytes();
      // Dekodiranje i isecanje velikih fotografija traje — van UI niti.
      final tiles = await Isolate.run(() => _buildTiles(bytes));
      if (tiles.isEmpty) return null;

      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().microsecondsSinceEpoch;
      for (var i = 0; i < tiles.length; i++) {
        final file = File('${dir.path}/ips_qr_tile_${stamp}_$i.jpg');
        await file.writeAsBytes(tiles[i], flush: true);
        fallbackFiles.add(file);
        final result = await _scanFile(file.path);
        if (result != null) return result;
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

  /// Seče sliku na mrežu 2×3 isečaka sa preklapanjem (QR na granici ostaje
  /// ceo bar u jednom isečku), donji red prvi jer je tu uplatnica. Mali isečci
  /// se uvećavaju 2× (nearest — ivice modula ostaju oštre); vrlo velike
  /// fotografije se prvo smanjuju da isečci ne bi bili preveliki za ML Kit.
  static List<Uint8List> _buildTiles(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return const [];
    var oriented = img.bakeOrientation(decoded);

    final maxDim = math.max(oriented.width, oriented.height);
    if (maxDim > 4000) {
      final factor = 4000 / maxDim;
      oriented = img.copyResize(
        oriented,
        width: (oriented.width * factor).round(),
        height: (oriented.height * factor).round(),
        interpolation: img.Interpolation.average,
      );
    }

    final w = oriented.width;
    final h = oriented.height;
    if (w < 200 || h < 200) return const [];

    final tileW = (w * 0.6).round();
    final tileH = (h * 0.45).round();
    final xs = [0, w - tileW];
    final ys = [h - tileH, ((h - tileH) / 2).round(), 0];

    final tiles = <Uint8List>[];
    for (final y in ys) {
      for (final x in xs) {
        var tile = img.copyCrop(
          oriented,
          x: x,
          y: y,
          width: tileW,
          height: tileH,
        );
        if (math.max(tile.width, tile.height) < 1500) {
          tile = img.copyResize(
            tile,
            width: tile.width * 2,
            height: tile.height * 2,
            interpolation: img.Interpolation.nearest,
          );
        }
        tiles.add(img.encodeJpg(tile, quality: 92));
      }
    }
    return tiles;
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
