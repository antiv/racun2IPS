import '../constants/ips.dart';
import '../models/invoice_data.dart';
import 'ips.dart';

/// Preslikava srpska ćirilična slova u latinicu (1-na-1) radi ravnopravnog
/// heurističkog prepoznavanja ćiriličnih uplatnica (EPS, Infostan, komunalije).
String cyrillicToLatin(String input) {
  const map = {
    'А': 'A', 'Б': 'B', 'В': 'V', 'Г': 'G', 'Д': 'D', 'Ђ': 'Đ', 'Е': 'E',
    'Ж': 'Ž', 'З': 'Z', 'И': 'I', 'Ј': 'J', 'К': 'K', 'Л': 'L', 'Љ': 'Lj',
    'М': 'M', 'Н': 'N', 'Њ': 'Nj', 'О': 'O', 'П': 'P', 'Р': 'R', 'С': 'S',
    'Т': 'T', 'Ћ': 'Ć', 'У': 'U', 'Ф': 'F', 'Х': 'H', 'Ц': 'C', 'Ч': 'Č',
    'Џ': 'Dž', 'Ш': 'Š',
    'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'ђ': 'đ', 'е': 'e',
    'ж': 'ž', 'з': 'z', 'и': 'i', 'ј': 'j', 'к': 'k', 'л': 'l', 'љ': 'lj',
    'м': 'm', 'н': 'n', 'њ': 'nj', 'о': 'o', 'п': 'p', 'р': 'r', 'с': 's',
    'т': 't', 'ћ': 'ć', 'у': 'u', 'ф': 'f', 'х': 'h', 'ц': 'c', 'ч': 'č',
    'џ': 'dž', 'ш': 'š',
  };
  final buf = StringBuffer();
  for (var i = 0; i < input.length; i++) {
    buf.write(map[input[i]] ?? input[i]);
  }
  return buf.toString();
}

/// Heuristički parser teksta sa srpskih računa i uplatnica (za lokalni OCR i clipboard).
///
/// Primenjuje strogi "Confidence Gate": vraća [InvoiceData] isključivo kada su:
/// 1. Broj računa (18 cifara) matematički validan po Modulo-97 algoritmu,
/// 2. Iznos (> 0) nedvosmisleno prepoznat uz ključne reči za uplatu/iznos,
/// 3. Naziv primaoca pronađen (min 3 karaktera),
/// 4. Poziv na broj validan (posebno Modulo-97 ako je na računu detektovan model 97).
///
/// Ako bilo koji od uslova nije zadovoljen, vraća `null` kako bi obrada
/// bezbedno prešla na Gemini AI fallback.
InvoiceData? tryParseInvoiceText(String rawText) {
  if (rawText.trim().isEmpty) return null;

  // 0. Ako tekst već sadrži sirovi NBS IPS QR string (npr. K:PR|V:01|...), parsiraj direktno.
  final ipsMatch = RegExp(r'K:(?:PR|EK)\|[^\r\n]+', caseSensitive: false)
      .firstMatch(rawText);
  if (ipsMatch != null) {
    final direct = parseIpsString(ipsMatch.group(0)!);
    if (direct != null && validateAccountNumber(direct.accountNumber)) {
      return direct;
    }
  }

  final latinText = cyrillicToLatin(rawText);
  final normalizedText = latinText.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = normalizedText
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  if (lines.isEmpty) return null;

  // 1. Broj računa (mora proći Modulo-97).
  final accountNumber = _extractValidAccountNumber(normalizedText, lines);
  if (accountNumber == null || !validateAccountNumber(accountNumber)) {
    return null;
  }

  // 2. Iznos (mora imati visok stepen pouzdanosti uz ključne reči).
  final amountResult = _extractAmount(normalizedText, lines);
  if (amountResult == null || amountResult <= 0) {
    return null;
  }

  // 3. Poziv na broj i model.
  final refResult = _extractReferenceNumber(normalizedText, lines);
  if (!refResult.isReliable) {
    return null;
  }

  // 4. Primalac.
  final recipientName = _extractRecipientName(lines, accountNumber);
  if (recipientName == null || recipientName.trim().length < 3) {
    return null;
  }

  // 5. Šifra plaćanja i svrha uplate.
  final paymentCode = _extractPaymentCode(lines);
  final purpose = _extractPurpose(lines) ?? 'Uplata po računu';

  return InvoiceData(
    recipientName: _clip(sanitizePipe(recipientName), IpsLimits.n),
    accountNumber: accountNumber,
    amount: amountResult,
    paymentCode: paymentCode,
    purpose: _clip(sanitizePipe(purpose), IpsLimits.s),
    referenceNumber: _clip(sanitizePipe(refResult.value), IpsLimits.ro),
  );
}

String _clip(String v, int max) => v.length > max ? v.substring(0, max) : v;

/// Pronalazi sve kandidate za broj računa, normalizuje ih na 18 cifara
/// i zadržava samo one koji prolaze Modulo-97 kontrolu.
String? _extractValidAccountNumber(String fullText, List<String> lines) {
  final candidates = <_ScoredCandidate<String>>[];

  // Regex 1: Format sa crticama (npr. 840-0000711171843-84 ili 160 - 123456 - 78)
  final dashedRegex =
      RegExp(r'\b(\d{3})\s*[-–—]\s*(\d{1,13})\s*[-–—]\s*(\d{2})\b');
  // Regex 2: Neprekidni niz od 18 cifara
  final flatRegex = RegExp(r'\b(\d{18})\b');

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final lowerLine = line.toLowerCase();
    final prevLower = i > 0 ? lines[i - 1].toLowerCase() : '';
    final context = '$prevLower $lowerLine';

    void evaluateRaw(String rawCandidate, int baseBonus) {
      final normalized = normalizeAccountNumber(rawCandidate);
      if (normalized.length != 18) return;
      final prefix = int.tryParse(normalized.substring(0, 3)) ?? 0;
      if (prefix < 100 || prefix > 999) return;
      if (!validateAccountNumber(normalized)) return;

      var score = 100 + baseBonus;
      if (context.contains('račun primaoca') ||
          context.contains('racun primaoca') ||
          context.contains('tekući račun') ||
          context.contains('tekuci racun') ||
          context.contains('žiro račun') ||
          context.contains('ziro racun') ||
          context.contains('uplatni račun') ||
          context.contains('broj računa')) {
        score += 50;
      }
      if (context.contains('račun platioca') ||
          context.contains('racun platioca') ||
          context.contains('račun uplatioca') ||
          context.contains('racun uplatioca')) {
        score -= 80;
      }
      candidates.add(_ScoredCandidate(normalized, score));
    }

    for (final m in dashedRegex.allMatches(line)) {
      evaluateRaw('${m.group(1)}-${m.group(2)}-${m.group(3)}', 20);
    }
    for (final m in flatRegex.allMatches(line)) {
      evaluateRaw(m.group(1)!, 0);
    }
  }

  if (candidates.isEmpty) return null;
  candidates.sort((a, b) => b.score.compareTo(a.score));
  return candidates.first.value;
}

/// Izvlači iznos za uplatu uz bodovanje konteksta (ključnih reči).
double? _extractAmount(String fullText, List<String> lines) {
  final candidates = <_ScoredCandidate<double>>[];

  // Srpski format iznosa sa 2 decimale: npr. = 1.234,56 ili 12.345,67 ili 450,00.
  // Lookaround sprečava da se deo datuma ("21.10.2026" → 21,10), dužeg broja
  // ili negativna vrednost (procenat "-24,62") pročita kao iznos.
  final amountRegex = RegExp(
    r'(?:=\s*)?(?<![\d.,\-])(\d{1,3}(?:[.\s]\d{3})+,\d{2}|\d+[.,]\d{2})(?![.,]?\d)',
  );

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final lower = line.toLowerCase();
    final prevLower = i > 0 ? lines[i - 1].toLowerCase() : '';
    final nextLower = i + 1 < lines.length ? lines[i + 1].toLowerCase() : '';
    // OCR po kolonama često vrati vrednost pre labele ("400,00" pa "Ukupno za
    // uplatu:"), pa se ključne reči traže i u sledećoj liniji — ali samo ako je
    // ona čista labela, a ne rečenica sa sopstvenim iznosom.
    final nextIsLabel = i + 1 < lines.length &&
        !amountRegex.hasMatch(lines[i + 1]);
    final context = '$prevLower $lower ${nextIsLabel ? nextLower : ''}';

    for (final match in amountRegex.allMatches(line)) {
      final fullMatch = match.group(0)!;
      final numStr = match.group(1)!;
      final parsed = _parseSerbianNumber(numStr);
      if (parsed == null || parsed <= 0 || parsed > 100000000) continue;

      var score = 0;

      // Znak '=' ispred iznosa je standard na srpskoj uplatnici (npr. "= 2.450,00")
      if (fullMatch.trimLeft().startsWith('=')) {
        score += 90;
      }

      // Najviši prioritet: eksplicitne fraze za konačni iznos računa
      if (_containsAny(context, const [
        'ukupno za uplatu',
        'iznos za uplatu',
        'svega za uplatu',
        'za uplatu',
        'za uplatiti',
        'za plaćanje',
        'za placanje',
        'uplatom od',
        'uplata od',
      ])) {
        score += 100;
      } else if (_containsAny(context, const [
        'iznos',
        'ukupno',
        'zaduženje',
        'zaduzenje',
      ])) {
        score += 55;
      }

      // Valuta u istoj ili susednoj liniji
      if (_containsAny(context, const ['rsd', 'din', 'дин'])) {
        score += 30;
      }

      // Negativni poeni za međuzbirove, poreze, očitanja brojila ili tarife
      if (_containsAny(lower, const [
        'osnovica',
        'stopa',
        'pdv',
        'kamata',
        'popust',
        'umanjenje',
        'kwh',
        'm3',
        'prethodni',
        'pretplata',
      ]) &&
          !_containsAny(lower, const [
            'za uplatu',
            'ukupno za uplatu',
            'uplatom od',
            'uplata od',
          ])) {
        score -= 60;
      }

      // Računi/uplatnice su obično u donjoj polovini dokumenta
      if (i >= lines.length ~/ 2) {
        score += 10;
      }

      candidates.add(_ScoredCandidate(parsed, score));
    }
  }

  if (candidates.isEmpty) return null;
  candidates.sort((a, b) => b.score.compareTo(a.score));

  // Confidence Gate: prihvatamo samo iznos koji ima jasnu kontekstualnu potvrdu
  if (candidates.first.score < 50) return null;
  return candidates.first.value;
}

double? _parseSerbianNumber(String raw) {
  final cleaned = raw.trim();
  if (cleaned.contains(',')) {
    // Format 1.234,56 -> ukloni tačke i razmake, zameni zarez tačkom
    final normalized = cleaned
        .replaceAll('.', '')
        .replaceAll(' ', '')
        .replaceAll(',', '.');
    return double.tryParse(normalized);
  } else {
    // Format 1234.56 (samo jedna tačka i 2 decimale na kraju)
    return double.tryParse(cleaned.replaceAll(' ', ''));
  }
}

class _RefExtraction {
  const _RefExtraction(this.value, {required this.isReliable});
  final String value;
  final bool isReliable;
}

/// Izvlači model i poziv na broj, uz proveru Modulo-97 kada je prisutan model 97.
_RefExtraction _extractReferenceNumber(String fullText, List<String> lines) {
  final lowerFull = fullText.toLowerCase();
  final mentionsRefOrModel = _containsAny(lowerFull, const [
    'poziv na broj',
    'odobrenje',
    'model',
  ]);
  final mentionsModel97 = RegExp(
    r'model[^\n\d]{0,15}97\b|\b97\s+[\dA-Z]{2}[-\s]?[\dA-Z]{3,}',
    caseSensitive: false,
  ).hasMatch(fullText);

  // 1. Pokušaj pronalaska eksplicitnog Modela 97 + poziva na broj koji prolazi Modulo-97
  final mod97Candidates = <String>[];

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final nextLine = i + 1 < lines.length ? lines[i + 1] : '';
    final combined = '$line $nextLine';

    // Traži patern: "97" praćen kontrolnim brojem i pozivom (sa razmacima/crticama)
    final mod97Regex = RegExp(
      r'\b97[\s-]*([0-9]{2}[\s-]*[0-9A-Z][0-9A-Z\s-]{3,22})\b',
      caseSensitive: false,
    );
    for (final m in mod97Regex.allMatches(combined)) {
      final tail = m.group(1)!.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
      final fullCandidate = '97$tail';
      final digitsOnly = fullCandidate.replaceAll(RegExp(r'[^0-9]'), '');
      if (digitsOnly.length == 18 && validateAccountNumber(digitsOnly)) {
        continue; // Ne mešaj 18-cifreni broj računa sa pozivom na broj
      }
      if (fullCandidate.length >= 6 &&
          fullCandidate.length <= IpsLimits.ro &&
          validateReferenceNumber(fullCandidate)) {
        mod97Candidates.add(fullCandidate);
      }
    }

    // Ako linija spominje "poziv na broj" ili "odobrenje", proveri i vrednost bez "97" na početku
    // kojoj dodajemo "97" ako je model 97 u posebnom boksu
    final lower = line.toLowerCase();
    if (_containsAny(lower, const ['poziv na broj', 'odobrenje', 'model'])) {
      final window = [
        line,
        if (i + 1 < lines.length) lines[i + 1],
        if (i + 2 < lines.length) lines[i + 2],
      ].join(' ');

      final tokenRegex =
          RegExp(r'\b([0-9]{2}[-\s]?[0-9A-Z][0-9A-Z-]{3,22})\b');
      for (final m in tokenRegex.allMatches(window)) {
        final rawToken = m.group(1)!.trim();
        final cleanDigits = rawToken.replaceAll(RegExp(r'[^0-9]'), '');
        if (cleanDigits.length == 18 && validateAccountNumber(cleanDigits)) {
          continue; // Preskoči broj računa
        }
        final clean = rawToken.replaceAll(RegExp(r'[\s-]'), '');
        if (clean.startsWith('97') &&
            clean.length >= 6 &&
            validateReferenceNumber(clean)) {
          mod97Candidates.add(clean);
        } else if (mentionsModel97) {
          final with97 = '97$clean';
          if (with97.length >= 6 &&
              with97.length <= IpsLimits.ro &&
              validateReferenceNumber(with97)) {
            mod97Candidates.add(with97);
          }
        }
      }
    }
  }

  if (mod97Candidates.isNotEmpty) {
    return _RefExtraction(mod97Candidates.first, isReliable: true);
  }

  // Ako račun eksplicitno zahteva Model 97, a nismo našli validan Mod97 poziv na broj,
  // ne smemo nagađati — prepusti Gemini AI-ju.
  if (mentionsModel97) {
    return const _RefExtraction('', isReliable: false);
  }

  // 2. Model 00 ili poziv na broj bez modela 97
  for (var i = 0; i < lines.length; i++) {
    final lower = lines[i].toLowerCase();
    if (_containsAny(lower, const ['poziv na broj', 'odobrenje'])) {
      // Na uplatnici je vrednost često 2-3 linije ispod labele (između su
      // labele susednih polja, npr. "Broj modela").
      // Ispod labele se gledaju samo redovi koji liče na vrednost (bez reči i
      // dvotačke) — inače se pokupi broj iz rečenice, npr. svrhe uplate
      // "Uplata po računu broj 21850/26".
      final searchLines = [
        lines[i],
        for (var k = i + 1; k <= i + 3 && k < lines.length; k++)
          if (!RegExp(r'[a-zčćžšđ:]').hasMatch(lines[k])) lines[k],
      ];
      for (final sLine in searchLines) {
        final cleanedLine = sLine.replaceFirst(
          RegExp(r'^.*?(?:poziv na broj|odobrenje)\s*[():\-]*\s*',
              caseSensitive: false),
          '',
        );
        final m = RegExp(r'\b(?:00[\s-]*)?([0-9][0-9A-Z-]{3,22})\b')
            .firstMatch(cleanedLine);
        if (m != null) {
          final token = m.group(1)!;
          final digitsOnly = token.replaceAll(RegExp(r'[^0-9]'), '');
          if (digitsOnly.length == 18 && validateAccountNumber(digitsOnly)) {
            continue;
          }
          final ref = '00${token.replaceAll(RegExp(r'\s+'), '')}';
          if (validateReferenceNumber(ref)) {
            return _RefExtraction(ref, isReliable: true);
          }
        }
      }
    }
  }

  // Ako se u tekstu pominje "poziv na broj", a nismo uspeli da ga izvučemo,
  // označavamo kao nepouzdano da bi AI preuzeo.
  if (mentionsRefOrModel) {
    return const _RefExtraction('', isReliable: false);
  }

  return const _RefExtraction('', isReliable: true);
}

final _entityRegex = RegExp(
  r'\b(J\.?K\.?P\.?|J\.?P\.?|D\.?O\.?O\.?|A\.?D\.?|EPS\s+SNABDEVANJE|ELEKTROPRIVREDA|INFOSTAN|INFORMATIKA|TELEKOM\s+SRBIJA|YETTEL|A1\s+SRBIJA|SBB\s|UPRAVA\s+ZA\s+TREZOR|PORESKA\s+UPRAVA|STAMBENA\s+ZAJEDNICA)\b',
  caseSensitive: false,
);

/// Imena platioca: prva ne-labela ispod svake labele "Platilac"/"Uplatilac".
/// OCR uplatnice po kolonama zna da ubaci platioca odmah ispod "Primalac".
Set<String> _payerNames(List<String> lines) {
  final names = <String>{};
  for (var i = 0; i < lines.length; i++) {
    final lower = lines[i].toLowerCase();
    if (!lower.startsWith('platilac') && !lower.startsWith('uplatilac')) continue;
    for (var k = i + 1; k <= i + 3 && k < lines.length; k++) {
      final candidate = lines[k].trim();
      final candLower = candidate.toLowerCase();
      // Sledeća labela polja — blok platioca je prazan u ovom redosledu.
      if (candLower.endsWith(':') || candLower.startsWith('primalac')) break;
      if (_isLabelOrNoise(candidate)) continue;
      names.add(candLower);
      break;
    }
  }
  return names;
}

/// Izvlači naziv primaoca iz linija oko labele "Primalac" ili prepoznaje pravnu formu.
String? _extractRecipientName(List<String> lines, String accountNumber) {
  final payers = _payerNames(lines);
  // 1. Traži eksplicitnu labelu "Primalac" (ali ne "Račun primaoca")
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final lower = line.toLowerCase();
    if ((lower.contains('primalac') ||
            lower.contains('naziv primaoca') ||
            lower.contains('prodavac') ||
            lower.contains('izdavalac')) &&
        !lower.contains('račun primaoca') &&
        !lower.contains('racun primaoca')) {
      // Slučaj A: "Primalac: JKP Infostan tehnologije Beograd" u istoj liniji
      final inline = line
          .replaceFirst(
            RegExp(
              r'^.*?(?:naziv primaoca|primalac|prodavac|izdavalac(?:\s+računa)?)\s*[:\-]\s*',
              caseSensitive: false,
            ),
            '',
          )
          .trim();
      if (inline.length >= 3 &&
          inline.toLowerCase() != line.toLowerCase() &&
          !_isLabelOrNoise(inline)) {
        return inline;
      }

      // Slučaj B: Naziv je u sledećim linijama ispod labele "Primalac".
      // Preskače se platilac; prednost ima pravno lice, pa linija bez cifara
      // (adrese platioca/primaoca obično imaju broj).
      final candidates = <String>[];
      for (var offset = 1; offset <= 4 && i + offset < lines.length; offset++) {
        final candidate = lines[i + offset].trim();
        if (candidate.length >= 3 &&
            !_isLabelOrNoise(candidate) &&
            !payers.contains(candidate.toLowerCase())) {
          candidates.add(candidate);
        }
      }
      if (candidates.isNotEmpty) {
        return candidates.firstWhere(
          _entityRegex.hasMatch,
          orElse: () => candidates.firstWhere(
            (c) => !RegExp(r'\d').hasMatch(c),
            orElse: () => candidates.first,
          ),
        );
      }
    }
  }

  // 2. Fallback: Prepoznaj liniju sa tipičnim srpskim privrednim subjektima / javnim preduzećima
  for (final line in lines) {
    if (_entityRegex.hasMatch(line) &&
        line.length >= 4 &&
        line.length <= 80 &&
        !_isLabelOrNoise(line)) {
      return line;
    }
  }

  return null;
}

/// Izvlači svrhu uplate ako je prisutna.
String? _extractPurpose(List<String> lines) {
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final lower = line.toLowerCase();
    if (lower.contains('svrha uplate') ||
        lower.contains('svrha plaćanja') ||
        lower.contains('svrha placanja')) {
      final inline = line
          .replaceFirst(
            RegExp(r'^.*?svrha\s+(?:uplate|plaćanja|placanja)\s*[:\-]?\s*',
                caseSensitive: false),
            '',
          )
          .trim();
      if (inline.length >= 3 &&
          inline.toLowerCase() != line.toLowerCase() &&
          !_isLabelOrNoise(inline)) {
        return inline;
      }
      for (var offset = 1; offset <= 4 && i + offset < lines.length; offset++) {
        final next = lines[i + offset].trim();
        if (next.length >= 3 && !_isLabelOrNoise(next)) {
          return next;
        }
      }
    }
  }
  return null;
}

/// Izvlači 3-cifrenu šifru plaćanja (i konvertuje gotovinske 1xx u 2xx).
String _extractPaymentCode(List<String> lines) {
  for (var i = 0; i < lines.length; i++) {
    final lower = lines[i].toLowerCase();
    if (lower.contains('šifra') || lower.contains('sifra')) {
      final window = [
        lines[i],
        if (i + 1 < lines.length) lines[i + 1],
      ].join(' ');
      final m = RegExp(r'\b([12]\d{2})\b').firstMatch(window);
      if (m != null) {
        final code = m.group(1)!;
        return code.startsWith('1') ? '2${code.substring(1)}' : code;
      }
    }
  }
  return '289';
}

bool _isLabelOrNoise(String text) {
  final lower = text.toLowerCase().trim();
  if (lower.isEmpty) return true;
  // Ako se sastoji samo od cifara, crtica i interpunkcije
  if (!RegExp(r'[a-zA-ZčćžšđČĆŽŠĐ]{2,}').hasMatch(lower)) return true;

  const forbiddenExact = {
    'uplatilac',
    'platilac',
    'svrha uplate',
    'svrha plaćanja',
    'svrha placanja',
    'primalac',
    'račun primaoca',
    'racun primaoca',
    'iznos',
    'šifra plaćanja',
    'sifra placanja',
    'valuta',
    'model',
    'poziv na broj',
    'poziv na broj (odobrenje)',
    'nalog za uplatu',
    'pečat i potpis',
    'rsd',
  };
  if (forbiddenExact.contains(lower)) return true;
  if (lower.startsWith('račun primaoca') ||
      lower.startsWith('racun primaoca') ||
      lower.startsWith('poziv na broj') ||
      lower.startsWith('šifra plaćanja') ||
      lower.startsWith('sifra placanja') ||
      lower.startsWith('uplatilac') ||
      lower.startsWith('platilac') ||
      lower.startsWith('model ') ||
      lower.startsWith('broj modela') ||
      lower.startsWith('tekući račun') ||
      lower.startsWith('tekuci racun') ||
      lower.startsWith('svrha uplate') ||
      lower.startsWith('šif') ||
      lower.startsWith('sif.') ||
      lower.startsWith('iznos') ||
      lower.startsWith('valuta')) {
    return true;
  }
  return false;
}

bool _containsAny(String haystack, List<String> needles) {
  for (final n in needles) {
    if (haystack.contains(n)) return true;
  }
  return false;
}

class _ScoredCandidate<T> {
  const _ScoredCandidate(this.value, this.score);
  final T value;
  final int score;
}
