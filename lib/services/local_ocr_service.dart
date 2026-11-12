import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../models/invoice_data.dart';
import '../utils/invoice_text_parser.dart';
import 'shared_image.dart';

/// Lokalni OCR servis koji kombinuje:
/// - `google_mlkit_text_recognition` (brzi latinični OCR i čitanje cifara),
/// - Nativni ćirilični OCR (`recognizeTextNative`):
///   - na Androidu: Tesseract 4 LSTM sa srpskim ćiriličnim modelom (`srp.traineddata`),
///   - na iOS-u: Apple Vision (`VNRecognizeTextRequest` sa nativnom podrškom za ćirilicu i latinicu).
///
/// Izvršava čitanje teksta na samom uređaju i pokušava ekstrakciju i
/// Modulo-97 validaciju podataka o računu. Ako podaci nisu potpuni ili ne
/// prolaze validaciju, vraća `null` kako bi se obrada prosledila na AI.
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
      if (result != null) return result;
      // Ako u normalnoj orijentaciji podaci nisu izvučeni (npr. uplatnica slikana
      // poprečno/bočno kamerom), probaj sliku okrenutu za 90° i 270°.
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
      // 1. Pokrećemo nativni OCR koji na sistemu ima model za ćirilicu:
      //    - Na Androidu: Tesseract 4 LSTM sa srpskim ćiriličnim modelom (`srp.traineddata`)
      //    - Na iOS-u: Apple Vision (`VNRecognizeTextRequest` sa ćirilicom i latinicom)
      final nativeOcr = await recognizeTextNative(filePath);

      // Brojimo ćirilična slova srpske azbuke u nativnom OCR tekstu.
      final cyrillicRegex = RegExp(r'[А-Яа-яЂђЈјЉљЊњЋћЏџ]');
      final cyrillicCount = nativeOcr != null
          ? cyrillicRegex.allMatches(nativeOcr.text).length
          : 0;
      final isCyrillic = cyrillicCount >= 8;

      if (isCyrillic && nativeOcr != null) {
        debugPrint(
          'LocalOcrService: Prepoznata ćirilica ($cyrillicCount slova) — koristim ćirilični OCR za CELU sliku (${nativeOcr.text.length} karaktera, ${nativeOcr.lines.length} segmenata)',
        );
        // ĆIRILIČNI OCR ZA CELU SLIKU:
        // Sva polja (primalac, svrha, račun, poziv na broj, iznos) se parsiraju
        // isključivo iz ćiriličnog OCR modela. Nema mešanja sa ML Kit-om.
        final cyrillicData = _parseFromOcrOutput(nativeOcr.text, nativeOcr.lines);
        if (cyrillicData != null) {
          debugPrint(
            'LocalOcrService (Ćirilica): Uspešno prepoznat primalac "${cyrillicData.recipientName}", račun: ${cyrillicData.accountNumber}, iznos: ${cyrillicData.amount}, poziv: ${cyrillicData.referenceNumber}',
          );
          return cyrillicData;
        }

        // Ako ćirilični model nije uspeo da izvuče validne podatke (npr. mutna slika,
        // nečitak račun), NIKADA ne podmećemo ML Kit latinične greške,
        // već vraćamo null kako bi se aktivirao MATE AI fallback.
        debugPrint(
          'LocalOcrService: Ćirilični račun nije prošao lokalnu validaciju -> AI fallback',
        );
        return null;
      }

      // 2. Dokument je na latinici (npr. račun SBB, Yettel, A1, Infostan na latinici):
      // Na iOS-u Apple Vision čita i latinicu, pa ga prvo proveravamo.
      if (Platform.isIOS && nativeOcr != null) {
        final visionLatinData = _parseFromOcrOutput(nativeOcr.text, nativeOcr.lines);
        if (visionLatinData != null && visionLatinData.referenceNumber.isNotEmpty) {
          return visionLatinData;
        }
      }

      // Za latinične račune na Androidu (ili dopunu na iOS-u) pokrećemo ML Kit.
      final inputImage = InputImage.fromFilePath(filePath);
      final recognized = await recognizer.processImage(inputImage);
      final mlLines = _linesFromMlKit(recognized);
      debugPrint(
        'LocalOcrService (ML Kit - latinica): prepoznato ${recognized.text.length} karaktera teksta',
      );

      return _parseFromOcrOutput(recognized.text, mlLines);
    } catch (e) {
      debugPrint('LocalOcrService processImage error: $e');
      return null;
    }
  }

  List<NativeOcrLine> _linesFromMlKit(RecognizedText recognized) {
    final out = <NativeOcrLine>[];
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        final text = line.text.trim();
        if (text.isEmpty) continue;
        out.add(
          NativeOcrLine(
            text: text,
            left: line.boundingBox.left,
            top: line.boundingBox.top,
            right: line.boundingBox.right,
            bottom: line.boundingBox.bottom,
          ),
        );
      }
    }
    return out;
  }

  /// Parsira OCR izlaz koristeći geometrijsku rekonstrukciju:
  /// 1. Vertikalni stupci (`_buildColumnTrackText`) — čuva složena polja uplatnice
  ///    (`Platilac`, `Svrha uplate`, `Primalac`, `Račun`, `Poziv na broj`) unutar iste kolone,
  /// 2. Prirodni redosled blokova (`fullText`),
  /// 3. Horizontalni redovi (`_buildHorizontalRowText`) — spaja levi opis stavke u tabeli
  ///    sa desnim iznosom na istoj Y visini i boks modela `97` sa pozivom na broj.
  InvoiceData? _parseFromOcrOutput(
    String fullText,
    List<NativeOcrLine> lines,
  ) {
    if (fullText.trim().isEmpty && lines.isEmpty) return null;

    final columnText = _buildColumnTrackText(lines);
    final rowText = _buildHorizontalRowText(lines);

    InvoiceData? colResult;
    if (columnText.isNotEmpty) {
      colResult = tryParseInvoiceText(
        columnText,
        horizontalRowsText: rowText.isNotEmpty ? rowText : null,
      );
    }

    final direct = tryParseInvoiceText(
      fullText,
      horizontalRowsText: rowText.isNotEmpty ? rowText : null,
    );

    InvoiceData? rowResult;
    if (rowText.isNotEmpty) {
      rowResult = tryParseInvoiceText(rowText);
    }

    final base = colResult ?? direct ?? rowResult;
    if (base == null) return null;

    // Dopuni iznos ili poziv na broj iz alternativnih rasporeda ako je potrebno.
    final extras = [rowResult, direct, colResult].whereType<InvoiceData>();
    for (final alt in extras) {
      if (alt.accountNumber != base.accountNumber) continue;
      if (base.amount <= 0 && alt.amount > 0) {
        base.amount = alt.amount;
      }
      if (base.referenceNumber.isEmpty && alt.referenceNumber.isNotEmpty) {
        base.referenceNumber = alt.referenceNumber;
      }
    }

    return base;
  }



  /// Geometrijski grupiše linije u vertikalne kolone (stupce) na osnovu
  /// horizontalnog preklapanja X-opsega, bez ikakvih fiksnih konstanti podele ekrana.
  /// Time svaka kolona uplatnice (leva kolona sa Platilac/Svrha/Primalac, srednja
  /// kolona sa Šifra/Iznos/Račun/Model/Poziv i desni talon) ostaje u sopstvenom
  /// vertikalnom toku od vrha ka dnu.
  String _buildColumnTrackText(List<NativeOcrLine> allLines) {
    if (allLines.length < 3) return '';

    var minX = double.infinity;
    var maxX = double.negativeInfinity;
    for (final l in allLines) {
      if (l.left < minX) minX = l.left;
      if (l.right > maxX) maxX = l.right;
    }
    final pageW = math.max(1.0, maxX - minX);

    final sortedByTop = List<NativeOcrLine>.of(allLines)
      ..sort((a, b) => a.top.compareTo(b.top));

    final tracks = <_VerticalTrack>[];

    for (final line in sortedByTop) {
      final lineH = math.max(1.0, line.bottom - line.top);
      final lineW = math.max(1.0, line.right - line.left);
      final isSpanning = lineW > pageW * 0.48;

      _VerticalTrack? bestTrack;
      var bestScore = double.negativeInfinity;

      for (final track in tracks) {
        final vGap = line.top - track.bottom;
        if (vGap < -lineH * 0.8 || vGap > lineH * 8.5) continue;

        final trackW = math.max(1.0, track.colRight - track.left);
        final overlap =
            math.min(track.colRight, line.right) -
            math.max(track.left, line.left);
        final minW = math.min(trackW, lineW);
        final leftDiff = (line.left - track.left).abs();

        if (leftDiff > math.max(lineH * 4.5, pageW * 0.14)) continue;

        final hasOverlap = overlap > minW * 0.22;
        final sharesLeftMargin =
            leftDiff <= lineH * 1.8 &&
            line.left <= track.colRight + lineH * 1.5;

        if (!hasOverlap && !sharesLeftMargin) continue;

        final score =
            (overlap / minW) * 100.0 -
            leftDiff * 0.5 -
            math.max(0.0, vGap) * 0.15;
        if (score > bestScore) {
          bestScore = score;
          bestTrack = track;
        }
      }

      if (bestTrack != null) {
        bestTrack.add(line, isSpanning: isSpanning);
      } else {
        tracks.add(_VerticalTrack(line, isSpanning: isSpanning, pageW: pageW));
      }
    }

    tracks.sort((a, b) {
      final xCmp = a.left.compareTo(b.left);
      return xCmp != 0 ? xCmp : a.top.compareTo(b.top);
    });

    final buffer = StringBuffer();
    for (final track in tracks) {
      track.lines.sort((a, b) => a.top.compareTo(b.top));
      for (final l in track.lines) {
        buffer.writeln(l.text);
      }
    }
    return buffer.toString();
  }

  /// Geometrijski spaja linije koje se nalaze na istoj horizontalnoj visini (Y)
  /// u zajednički red (sortiran sleva nadesno). Ako se nakon numeričke kolone
  /// (iznosa u tabeli) posle većeg horizontalnog razmaka pojavi nov tekstualni
  /// stubac (npr. bočni tekst ili talon), prelama ga u novi red.
  String _buildHorizontalRowText(List<NativeOcrLine> allLines) {
    if (allLines.length < 3) return '';

    double cy(NativeOcrLine l) => (l.top + l.bottom) / 2.0;
    double height(NativeOcrLine l) => math.max(1.0, l.bottom - l.top);
    double width(NativeOcrLine l) => math.max(1.0, l.right - l.left);

    bool overlapsHorizontally(NativeOcrLine a, NativeOcrLine b) {
      final overlap = math.min(a.right, b.right) - math.max(a.left, b.left);
      return overlap > math.min(width(a), width(b)) * 0.25;
    }

    final sorted = List<NativeOcrLine>.of(allLines)
      ..sort((a, b) => cy(a).compareTo(cy(b)));

    final rows = <List<NativeOcrLine>>[];
    for (final line in sorted) {
      if (rows.isEmpty) {
        rows.add([line]);
        continue;
      }
      final prevRow = rows.last;
      var sumCy = 0.0;
      var sumH = 0.0;
      for (final item in prevRow) {
        sumCy += cy(item);
        sumH += height(item);
      }
      final avgCy = sumCy / prevRow.length;
      final avgH = sumH / prevRow.length;
      final sameRowY =
          (cy(line) - avgCy).abs() <= math.max(avgH, height(line)) * 0.55;
      final hasXOverlap = prevRow.any((x) => overlapsHorizontally(line, x));
      if (sameRowY && !hasXOverlap) {
        prevRow.add(line);
      } else {
        rows.add([line]);
      }
    }

    final hasLettersRegex = RegExp(
      r'[A-Za-zČĆŽŠĐčćžšđА-Яа-яЂђЈјЉљЊњЋћЏџ]{2,}',
    );
    final endsWithAmountRegex = RegExp(r'\d+[.,]\d{2}\s*$');

    final buffer = StringBuffer();
    for (final row in rows) {
      row.sort((a, b) => a.left.compareTo(b.left));
      final currentLine = StringBuffer(row.first.text);
      for (var i = 1; i < row.length; i++) {
        final prev = row[i - 1];
        final curr = row[i];
        final gap = curr.left - prev.right;
        final rowH = math.max(height(prev), height(curr));

        // Ako prethodna ćelija završava decimalnim iznosom (desna ivica tabele),
        // a sledeća ćelija posle razmaka počinje novim tekstom (susedna tabela/stubac),
        // odvoji je novim redom umesto spajanja u isti red tabele.
        if (gap > rowH * 1.5 &&
            endsWithAmountRegex.hasMatch(prev.text) &&
            hasLettersRegex.hasMatch(curr.text)) {
          buffer.writeln(currentLine.toString());
          currentLine
            ..clear()
            ..write(curr.text);
        } else {
          currentLine.write('   ${curr.text}');
        }
      }
      buffer.writeln(currentLine.toString());
    }
    return buffer.toString();
  }
}

class _VerticalTrack {
  _VerticalTrack(
    NativeOcrLine first, {
    required bool isSpanning,
    required double pageW,
  }) : lines = [first],
       left = first.left,
       top = first.top,
       right = first.right,
       colRight = isSpanning
           ? math.min(first.right, first.left + pageW * 0.35)
           : first.right,
       bottom = first.bottom;

  final List<NativeOcrLine> lines;
  double left;
  double top;
  double right;
  double colRight;
  double bottom;

  void add(NativeOcrLine line, {required bool isSpanning}) {
    lines.add(line);
    left = math.min(left, line.left);
    top = math.min(top, line.top);
    right = math.max(right, line.right);
    if (!isSpanning) {
      colRight = math.max(colRight, line.right);
    }
    bottom = math.max(bottom, line.bottom);
  }
}
