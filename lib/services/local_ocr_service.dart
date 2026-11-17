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
      final attempt = await _recognizeAndParse(
        recognizer,
        filePath,
        allowAltMode: true,
      );
      if (attempt.data != null) return attempt.data;
      // Ako u normalnoj orijentaciji podaci nisu izvučeni (npr. uplatnica slikana
      // poprečno/bočno kamerom), probaj sliku okrenutu za 270° i 90°.
      return await _recognizeRotated(
        recognizer,
        filePath,
        allowAltMode: attempt.abortedForRotation,
      );
    } finally {
      await recognizer.close();
    }
  }

  Future<InvoiceData?> _recognizeRotated(
    TextRecognizer recognizer,
    String filePath, {
    required bool allowAltMode,
  }) async {
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
        final attempt = await _recognizeAndParse(
          recognizer,
          file.path,
          allowAltMode: allowAltMode,
        );
        if (attempt.data != null) {
          debugPrint('LocalOcrService: uspešno parsirano iz okrenute slike');
          return attempt.data;
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
      for (final angle in const [270, 90])
        img.encodeJpg(img.copyRotate(upright, angle: angle), quality: 92),
    ];
  }

  Future<({InvoiceData? data, bool abortedForRotation})> _recognizeAndParse(
    TextRecognizer recognizer,
    String filePath, {
    required bool allowAltMode,
  }) async {
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
        // Ako su višeslovni segmenti izrazito vertikalni (npr. 79 vert vs 0 horiz),
        // slika je okrenuta bočno (90°/270°), pa odmah prelazimo na _recognizeRotated
        // kako se vertikalne kolone ne bi pogrešno spajale po Y-osi.
        if (_isSidewaysText(nativeOcr.lines)) {
          return (data: null, abortedForRotation: true);
        }

        debugPrint(
          'LocalOcrService: Prepoznata ćirilica ($cyrillicCount slova) — koristim ćirilični OCR za CELU sliku (${nativeOcr.text.length} karaktera, ${nativeOcr.lines.length} segmenata)',
        );
        final mlData = Platform.isAndroid
            ? await _readMlNumericData(recognizer, filePath)
            : null;

        var cyrillicData = _parseCyrillicWithMl(nativeOcr, mlData);
        // Ako primarna čista slika nije izvukla sve obavezne podatke (npr. jaka senka
        // ruke/telefona na papiru), probaj morfološku normalizaciju pozadine (mode: 1).
        if (cyrillicData == null && Platform.isAndroid && allowAltMode) {
          final shadowOcr = await recognizeTextNative(filePath, mode: 1);
          if (shadowOcr != null && !_isSidewaysText(shadowOcr.lines)) {
            cyrillicData = _parseCyrillicWithMl(shadowOcr, mlData);
          }
        }
        if (cyrillicData != null) {
          debugPrint(
            'LocalOcrService (Ćirilica): Uspešno prepoznat primalac "${cyrillicData.recipientName}", svrha: "${cyrillicData.purpose}", račun: ${cyrillicData.accountNumber}, iznos: ${cyrillicData.amount}, poziv: ${cyrillicData.referenceNumber}',
          );
          return (data: cyrillicData, abortedForRotation: false);
        }

        debugPrint(
          'LocalOcrService: Ćirilični račun nije prošao lokalnu validaciju -> sledeći korak / AI fallback',
        );
        return (data: null, abortedForRotation: false);
      }

      // 2. Dokument je na latinici (npr. račun SBB, Yettel, A1, Infostan na latinici):
      // Na iOS-u Apple Vision čita i latinicu, pa ga prvo proveravamo.
      InvoiceData? visionLatinFallback;
      if (Platform.isIOS && nativeOcr != null) {
        visionLatinFallback = _parseFromOcrOutput(
          nativeOcr.text,
          nativeOcr.lines,
        );
        if (visionLatinFallback != null &&
            visionLatinFallback.referenceNumber.isNotEmpty) {
          return (data: visionLatinFallback, abortedForRotation: false);
        }
      }

      // Za latinične račune na Androidu (ili dopunu na iOS-u) pokrećemo ML Kit.
      final inputImage = InputImage.fromFilePath(filePath);
      final recognized = await recognizer.processImage(inputImage);
      final mlLines = _linesFromMlKit(recognized);
      debugPrint(
        'LocalOcrService (ML Kit - latinica): prepoznato ${recognized.text.length} karaktera teksta',
      );

      final latinResult =
          _parseFromOcrOutput(recognized.text, mlLines) ?? visionLatinFallback;
      if (latinResult != null) {
        return (data: latinResult, abortedForRotation: false);
      }

      // Ako je na Androidu u mode=0 viđeno malo ćirilice (< 8 slova, npr. zbog
      // tamne senke), a ni ML Kit latinica nije prošla, probaj mode=1 pre AI/rotacije.
      if (Platform.isAndroid && allowAltMode) {
        final shadowOcr = await recognizeTextNative(filePath, mode: 1);
        final shadowCyrCount = shadowOcr != null
            ? cyrillicRegex.allMatches(shadowOcr.text).length
            : 0;
        if (shadowOcr != null && shadowCyrCount >= 8) {
          if (_isSidewaysText(shadowOcr.lines)) {
            return (data: null, abortedForRotation: true);
          }
          final mlRowText = _buildHorizontalRowText(mlLines);
          final parts = <String>[
            if (recognized.text.trim().isNotEmpty) recognized.text.trim(),
            if (mlRowText.trim().isNotEmpty) mlRowText.trim(),
          ];
          final mlData = (rawText: parts.join('\n'), mlLines: mlLines);
          final shadowData = _parseCyrillicWithMl(shadowOcr, mlData);
          if (shadowData != null) {
            debugPrint(
              'LocalOcrService (Ćirilica - senka): Uspešno prepoznat primalac "${shadowData.recipientName}", svrha: "${shadowData.purpose}", račun: ${shadowData.accountNumber}, iznos: ${shadowData.amount}, poziv: ${shadowData.referenceNumber}',
            );
            return (data: shadowData, abortedForRotation: false);
          }
        }
      }

      return (data: null, abortedForRotation: false);
    } catch (e) {
      debugPrint('LocalOcrService processImage error: $e');
      return (data: null, abortedForRotation: false);
    }
  }

  bool _isSidewaysText(List<NativeOcrLine> lines) {
    var horizCount = 0;
    var vertCount = 0;
    for (final l in lines) {
      if (l.text.length < 6) continue;
      final w = l.right - l.left;
      final h = l.bottom - l.top;
      if (h > w * 2.0) {
        vertCount++;
      } else if (w >= h * 1.2) {
        horizCount++;
      }
    }
    if (vertCount >= 10 && vertCount > horizCount * 2) {
      debugPrint(
        'LocalOcrService: Detektovan bočno rotiran tekst ($vertCount vert vs $horizCount horiz) -> prelazim na rotirane varijante',
      );
      return true;
    }
    return false;
  }

  Future<({String rawText, List<NativeOcrLine> mlLines})> _readMlNumericData(
    TextRecognizer recognizer,
    String filePath,
  ) async {
    final inputImage = InputImage.fromFilePath(filePath);
    final mlRecognized = await recognizer.processImage(inputImage);
    final mlLines = _linesFromMlKit(mlRecognized);
    final mlRowText = _buildHorizontalRowText(mlLines);
    final parts = <String>[
      if (mlRecognized.text.trim().isNotEmpty) mlRecognized.text.trim(),
      if (mlRowText.trim().isNotEmpty) mlRowText.trim(),
    ];
    return (rawText: parts.join('\n'), mlLines: mlLines);
  }

  InvoiceData? _parseCyrillicWithMl(
    NativeOcrResult ocr,
    ({String rawText, List<NativeOcrLine> mlLines})? mlData,
  ) {
    String? numericFallback;
    if (mlData != null) {
      final hybridAmountText = _buildHybridAmountRowText(
        ocr.lines,
        mlData.mlLines,
      );
      final parts = <String>[
        if (mlData.rawText.isNotEmpty) mlData.rawText,
        if (hybridAmountText.trim().isNotEmpty) hybridAmountText.trim(),
      ];
      if (parts.isNotEmpty) {
        numericFallback = parts.join('\n');
      }
    }
    return _parseFromOcrOutput(
      ocr.text,
      ocr.lines,
      numericFallbackText: numericFallback,
    );
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
    List<NativeOcrLine> lines, {
    String? numericFallbackText,
  }) {
    if (fullText.trim().isEmpty && lines.isEmpty) return null;

    final columnText = _buildColumnTrackText(lines);
    final rowText = _buildHorizontalRowText(lines);

    InvoiceData? colResult;
    if (columnText.isNotEmpty) {
      colResult = tryParseInvoiceText(
        columnText,
        horizontalRowsText: rowText.isNotEmpty ? rowText : null,
        numericFallbackText: numericFallbackText,
      );
    }

    final direct = tryParseInvoiceText(
      fullText,
      horizontalRowsText: rowText.isNotEmpty ? rowText : null,
      numericFallbackText: numericFallbackText,
    );

    InvoiceData? rowResult;
    if (rowText.isNotEmpty) {
      rowResult = tryParseInvoiceText(
        rowText,
        numericFallbackText: numericFallbackText,
      );
    }

    final base = colResult ?? direct ?? rowResult;
    if (base == null) return null;

    // Dopuni iznos, poziv na broj, naziv primaoca ili svrhu uplate iz
    // alternativnih rasporeda ako je u primarnom rasporedu došlo do cepanja kolone.
    final extras = [direct, rowResult, colResult].whereType<InvoiceData>();
    for (final alt in extras) {
      if (alt.accountNumber != base.accountNumber) continue;
      if (base.amount <= 0 && alt.amount > 0) {
        base.amount = alt.amount;
      }
      if ((base.referenceNumber.isEmpty ||
              (!base.referenceNumber.startsWith('97') &&
                  alt.referenceNumber.startsWith('97'))) &&
          alt.referenceNumber.isNotEmpty) {
        base.referenceNumber = alt.referenceNumber;
      }
      if (isBetterPurpose(alt.purpose, current: base.purpose)) {
        base.purpose = alt.purpose;
      }
      if (isBetterRecipientName(
        alt.recipientName,
        current: base.recipientName,
      )) {
        base.recipientName = alt.recipientName;
      }
    }

    return base;
  }

  /// Geometrijski grupiše linije u vertikalne kolone (stupce) na osnovu
  /// horizontalnog preklapanja X-opsega, bez ikakvih fiksnih konstanti podele ekrana.
  /// Time svaka kolona uplatnice (leva kolona sa Platilac/Svrha/Primalac, srednja
  /// kolona sa Šifra/Iznos/Račun/Model/Poziv i desni talon) ostaje u sopstvenom
  /// vertikalnom toku od vrha ka dnu, čak i kada je slika sa kamere blago nagnuta
  /// ili je tekst unutar okvira uplatnice uvučen u odnosu na labelu.
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
        if (vGap < -lineH * 0.85 || vGap > lineH * 9.5) continue;

        // Efektivna desna ivica kolone uzima u obzir da prva linija u koloni
        // može biti kratka labela (npr. "Платилац:" ili "Прималац:"), ali ne
        // sme prelaziti u susednu kolonu uplatnice.
        final effectiveColRight = math.max(
          track.colRight,
          track.recentLeft + lineH * 5.0,
        );
        final trackW = math.max(1.0, effectiveColRight - track.left);
        final overlap =
            math.min(effectiveColRight, line.right) -
            math.max(track.left, line.left);
        final minW = math.min(trackW, lineW);

        // Poredi X poziciju sa poslednjom linijom u tragu (otporno na nagib kamere 2-5°)
        // kao i sa početnom marginom traga.
        final leftDiffRecent = (line.left - track.recentLeft).abs();
        final leftDiffAnchor = (line.left - track.left).abs();
        final leftDiff = math.min(leftDiffRecent, leftDiffAnchor);

        if (line.left > effectiveColRight + lineH * 1.0) continue;
        if (leftDiff > math.max(lineH * 3.5, pageW * 0.06)) continue;

        final hasOverlap = overlap > minW * 0.25;
        final sharesLeftMargin =
            leftDiff <= math.max(lineH * 2.0, pageW * 0.04) &&
            line.left <= effectiveColRight + lineH * 0.8;
        // Tekst uvučen udesno unutar istog boksa uplatnice (npr. centriran naziv
        // primaoca ili svrha uplate ispod kratke labele "Прималац:"):
        final isIndentedInBox =
            !isSpanning &&
            line.left >= track.recentLeft - lineH * 1.0 &&
            line.left <= track.recentLeft + lineH * 3.5 &&
            line.right <= effectiveColRight + lineH * 3.0;

        if (!hasOverlap && !sharesLeftMargin && !isIndentedInBox) continue;

        final overlapRatio = math.max(0.0, overlap) / minW;
        final score =
            overlapRatio * 100.0 - leftDiff * 0.4 - math.max(0.0, vGap) * 0.15;
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

    // Ako je uvučeni pod-blok unutar iste kolone ipak napravio manji zaseban trag
    // čiji X-opseg leži unutar glavnog traga te kolone, pripoji ga glavnom tragu
    // kako bi linije ostale u tačnom vertikalnom redosledu od vrha ka dnu.
    if (tracks.length > 1) {
      final merged = <_VerticalTrack>[];
      tracks.sort((a, b) => b.lines.length.compareTo(a.lines.length));
      for (final t in tracks) {
        _VerticalTrack? host;
        for (final m in merged) {
          final avgH = m.lines.isEmpty
              ? 20.0
              : math.max(1.0, m.lines.first.bottom - m.lines.first.top);
          final xContained =
              t.left >= m.left - avgH * 1.5 &&
              t.colRight <= m.colRight + avgH * 2.0;
          if (!xContained) continue;
          // Ne spajaj ako imaju linije koje se horizontalno sudaraju na istoj Y visini.
          final hasYCollision = t.lines.any(
            (tl) => m.lines.any((ml) {
              final h = math.max(
                1.0,
                math.min(tl.bottom - tl.top, ml.bottom - ml.top),
              );
              final sameY =
                  ((tl.top + tl.bottom) - (ml.top + ml.bottom)).abs() * 0.5 <
                  h * 0.55;
              final xGap =
                  math.max(tl.left, ml.left) - math.min(tl.right, ml.right);
              return sameY && xGap > h * 1.2;
            }),
          );
          if (!hasYCollision) {
            host = m;
            break;
          }
        }
        if (host != null) {
          for (final l in t.lines) {
            final lw = math.max(1.0, l.right - l.left);
            host.add(l, isSpanning: lw > pageW * 0.48);
          }
        } else {
          merged.add(t);
        }
      }
      tracks
        ..clear()
        ..addAll(merged);
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

    final hasLettersRegex = RegExp(r'[A-Za-zČĆŽŠĐčćžšđА-Яа-яЂђЈјЉљЊњЋћЏџ]{2,}');
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

  /// Gradi pomoćni tekst horizontalnih redova za numerički fallback spajajući
  /// ćirilične labele iz Tesseract-a (poput "В ЗА УПЛАТУ..." na levoj strani
  /// tabele) sa numeričkim iznosima iz ML Kit-a na istoj Y visini.
  String _buildHybridAmountRowText(
    List<NativeOcrLine> cyrLines,
    List<NativeOcrLine> mlLines,
  ) {
    if (cyrLines.isEmpty || mlLines.isEmpty) return '';

    final hasCyrillicWords = RegExp(r'[А-Яа-яЂђЈјЉљЊњЋћЏџ]{2,}');
    final pureNumericOrAmount = RegExp(r'^[=\s]*\d[\d\s.,\-]{1,24}$');
    final amountTokenRegex = RegExp(
      r'(?:=\s*)?(?<![\d.,\-])(\d{1,3}(?:[.\s]\d{3})+\s*[.,]\s*\d{2}|\d+\s*[.,]\s*\d{2})(?![.,]?\d|\s*%)',
    );

    final numericMl = <NativeOcrLine>[];
    for (final ml in mlLines) {
      final t = ml.text.trim();
      if (pureNumericOrAmount.hasMatch(t)) {
        numericMl.add(ml);
      } else {
        final matches = amountTokenRegex.allMatches(t).toList();
        if (matches.isNotEmpty) {
          final m = matches.last;
          numericMl.add(
            NativeOcrLine(
              text: m.group(0)!.trim(),
              left: ml.right - math.min(80.0, (ml.right - ml.left) * 0.35),
              top: ml.top,
              right: ml.right,
              bottom: ml.bottom,
            ),
          );
        }
      }
    }
    if (numericMl.isEmpty) return '';

    final cyrLabelLines = cyrLines
        .where((cl) => hasCyrillicWords.hasMatch(cl.text))
        .toList();
    return _buildHorizontalRowText(<NativeOcrLine>[
      ...cyrLabelLines,
      ...numericMl,
    ]);
  }
}

class _VerticalTrack {
  _VerticalTrack(
    NativeOcrLine first, {
    required bool isSpanning,
    required double pageW,
  }) : lines = [first],
       left = first.left,
       recentLeft = first.left,
       top = first.top,
       right = first.right,
       colRight = isSpanning
           ? math.min(first.right, first.left + pageW * 0.35)
           : first.right,
       bottom = first.bottom;

  final List<NativeOcrLine> lines;
  double left;
  double recentLeft;
  double top;
  double right;
  double colRight;
  double bottom;

  void add(NativeOcrLine line, {required bool isSpanning}) {
    lines.add(line);
    left = math.min(left, line.left);
    if (!isSpanning) {
      // Blago prilagođavanje leve margine prati nagib kamere od vrha ka dnu,
      // ali bez naglog skoka kada je pojedinačna linija uvučena udesno.
      recentLeft = recentLeft * 0.65 + line.left * 0.35;
    }
    top = math.min(top, line.top);
    right = math.max(right, line.right);
    if (!isSpanning) {
      colRight = math.max(colRight, line.right);
    }
    bottom = math.max(bottom, line.bottom);
  }
}
