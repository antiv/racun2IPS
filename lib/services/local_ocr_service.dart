import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../models/invoice_data.dart';
import '../utils/invoice_text_parser.dart';

/// Lokalni OCR servis baziran na `google_mlkit_text_recognition`.
///
/// Izvršava brzo čitanje teksta na samom uređaju i pokušava ekstrakciju i
/// Modulo-97 validaciju podataka o računu. Ako podaci nisu potpuni ili ne
/// prolaze validaciju, vraća `null` kako bi se obrada prosledila na Gemini AI.
class LocalOcrService {
  /// Pokreće lokalni OCR nad bajtovima slike i vraća [InvoiceData] samo ako
  /// izvučeni podaci prolaze strogu validaciju (Confidence Gate).
  Future<InvoiceData?> tryExtractFromBytes(Uint8List imageBytes) async {
    File? tempFile;
    try {
      final dir = await getTemporaryDirectory();
      tempFile = File(
        '${dir.path}/ips_ocr_scan_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await tempFile.writeAsBytes(imageBytes, flush: true);
      return await tryExtractFromFile(tempFile.path);
    } catch (e) {
      debugPrint('LocalOcrService error: $e');
      return null;
    } finally {
      try {
        if (tempFile != null && await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
    }
  }

  /// Pokreće lokalni OCR nad fajlom slike na putanji [filePath].
  Future<InvoiceData?> tryExtractFromFile(String filePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await _recognizeAndParse(recognizer, filePath);
      if (result != null || !Platform.isIOS) return result;
      // ML Kit na iOS-u (za razliku od Androida) ne čita bočno okrenut tekst,
      // npr. uplatnicu slikanu poprečno — probaj sliku okrenutu za 90° i 270°.
      return await _recognizeRotated(recognizer, filePath);
    } finally {
      await recognizer.close();
    }
  }

  Future<InvoiceData?> _recognizeRotated(
    TextRecognizer recognizer,
    String filePath,
  ) async {
    final rotatedFiles = <File>[];
    try {
      final bytes = await File(filePath).readAsBytes();
      final variants = await Isolate.run(() => _rotatedVariants(bytes));
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().microsecondsSinceEpoch;
      for (var i = 0; i < variants.length; i++) {
        final file = File('${dir.path}/ips_ocr_rotated_${stamp}_$i.jpg');
        await file.writeAsBytes(variants[i], flush: true);
        rotatedFiles.add(file);
        final result = await _recognizeAndParse(recognizer, file.path);
        if (result != null) {
          debugPrint('LocalOcrService: uspešno parsirano iz okrenute slike');
          return result;
        }
      }
      return null;
    } catch (e) {
      debugPrint('LocalOcrService rotation error: $e');
      return null;
    } finally {
      for (final f in rotatedFiles) {
        try {
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
  }

  /// Slika okrenuta za 90° i 270° (EXIF rotacija upisana u piksele), smanjena
  /// na najviše 3000px da OCR ostane brz.
  static List<Uint8List> _rotatedVariants(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return const [];
    var upright = img.bakeOrientation(decoded);
    final longest = math.max(upright.width, upright.height);
    if (longest > 3000) {
      final factor = 3000 / longest;
      upright = img.copyResize(
        upright,
        width: (upright.width * factor).round(),
        height: (upright.height * factor).round(),
        interpolation: img.Interpolation.average,
      );
    }
    return [
      for (final angle in const [90, 270])
        img.encodeJpg(img.copyRotate(upright, angle: angle), quality: 92),
    ];
  }

  Future<InvoiceData?> _recognizeAndParse(
    TextRecognizer recognizer,
    String filePath,
  ) async {
    try {
      final inputImage = InputImage.fromFilePath(filePath);
      final recognized = await recognizer.processImage(inputImage);
      debugPrint(
        'LocalOcrService: prepoznato ${recognized.text.length} karaktera teksta',
      );
      if (recognized.text.trim().isEmpty) return null;

      // 1. Pokušaj parsiranja nad prirodnim redosledom blokova iz ML Kit-a.
      final direct = tryParseInvoiceText(recognized.text);
      if (direct != null) {
        debugPrint(
          'LocalOcrService: uspešno parsirano direktno iz blokova teksta',
        );
        return direct;
      }

      // 2. Na uplatnicama (dve kolone: levo Primalac/Svrha, desno Iznos/Račun/Poziv)
      // ML Kit nekada grupiše labele i vrednosti u odvojene blokove. Rekonstruiši
      // tekst po kolonama (leva kolona od vrha ka dnu, pa desna kolona od vrha ka dnu).
      final columnOrdered = _buildColumnOrderedText(recognized);
      if (columnOrdered.isNotEmpty && columnOrdered != recognized.text) {
        final colResult = tryParseInvoiceText(columnOrdered);
        if (colResult != null) {
          debugPrint('LocalOcrService: uspešno parsirano iz kolona uplatnice');
          return colResult;
        }
      }

      return null;
    } catch (e) {
      debugPrint('LocalOcrService processImage error: $e');
      return null;
    }
  }

  /// Sortira tekstualne linije po levoj i desnoj koloni dokumenta/uplatnice,
  /// čime se sprečava mešanje levih labela ("Primalac") sa desnim poljima ("Model").
  String _buildColumnOrderedText(RecognizedText recognized) {
    final allLines = <TextLine>[];
    for (final block in recognized.blocks) {
      allLines.addAll(block.lines);
    }
    if (allLines.length < 3) return '';

    var minX = double.infinity;
    var maxX = double.negativeInfinity;
    for (final line in allLines) {
      minX = math.min(minX, line.boundingBox.left);
      maxX = math.max(maxX, line.boundingBox.right);
    }
    if (!minX.isFinite || !maxX.isFinite || maxX <= minX) return '';

    final midX = minX + (maxX - minX) * 0.45;
    final leftCol = <TextLine>[];
    final rightCol = <TextLine>[];

    for (final line in allLines) {
      if (line.boundingBox.left < midX) {
        leftCol.add(line);
      } else {
        rightCol.add(line);
      }
    }

    int compareByTop(TextLine a, TextLine b) =>
        a.boundingBox.top.compareTo(b.boundingBox.top);

    leftCol.sort(compareByTop);
    rightCol.sort(compareByTop);

    final buffer = StringBuffer();
    for (final line in leftCol) {
      buffer.writeln(line.text);
    }
    for (final line in rightCol) {
      buffer.writeln(line.text);
    }
    return buffer.toString();
  }
}
