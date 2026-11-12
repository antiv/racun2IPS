import '../constants/ips.dart';
import '../models/invoice_data.dart';
import 'ips.dart';

/// Preslikava ćirilična slova u latinicu (1-na-1) radi ravnopravnog
/// prepoznavanja svih ćiriličnih uplatnica i računa. Pored standardnih 30 slova
/// srpske azbuke (Tesseract `srp`), obuhvata i rusko/ukrajinske digrafe i slova
/// (`нь` -> `nj`, `ль` -> `lj`, `ть` -> `ć`, `і/й` -> `j`) koje ugrađeni
/// Apple Vision OCR ponekad koristi pri čitanju srpske ćirilice na iOS-u.
String cyrillicToLatin(String input) {
  var text = input;
  const digraphs = <(String, String)>[
    ('НЬ', 'NJ'),
    ('Нь', 'Nj'),
    ('нь', 'nj'),
    ('ЛЬ', 'LJ'),
    ('Ль', 'Lj'),
    ('ль', 'lj'),
    ('ТЬ', 'Ć'),
    ('Ть', 'Ć'),
    ('ть', 'ć'),
    ('ТЄ', 'ĆE'),
    ('Тє', 'Će'),
    ('тє', 'će'),
    ('ДЖ', 'DŽ'),
    ('Дж', 'Dž'),
    ('дж', 'dž'),
  ];
  for (final (from, to) in digraphs) {
    if (text.contains(from)) {
      text = text.replaceAll(from, to);
    }
  }

  const map = {
    'А': 'A',
    'Б': 'B',
    'В': 'V',
    'Г': 'G',
    'Д': 'D',
    'Ђ': 'Đ',
    'Ѓ': 'Đ',
    'Е': 'E',
    'Ё': 'E',
    'Э': 'E',
    'Є': 'Je',
    'Ж': 'Ž',
    'З': 'Z',
    'Ѕ': 'Dz',
    'И': 'I',
    'Ы': 'I',
    'І': 'J',
    'Ї': 'Ji',
    'Й': 'J',
    'Ј': 'J',
    'К': 'K',
    'Л': 'L',
    'Љ': 'Lj',
    'М': 'M',
    'Н': 'N',
    'Њ': 'Nj',
    'О': 'O',
    'П': 'P',
    'Р': 'R',
    'С': 'S',
    'Т': 'T',
    'Ћ': 'Ć',
    'Ќ': 'Ć',
    'У': 'U',
    'Ф': 'F',
    'Х': 'H',
    'Ц': 'C',
    'Ч': 'Č',
    'Џ': 'Dž',
    'Ш': 'Š',
    'Щ': 'Šć',
    'Ю': 'Ju',
    'Я': 'Ja',
    'Ъ': '',
    'Ь': '',
    'а': 'a',
    'б': 'b',
    'в': 'v',
    'г': 'g',
    'д': 'd',
    'ђ': 'đ',
    'ѓ': 'đ',
    'е': 'e',
    'ё': 'e',
    'э': 'e',
    'є': 'je',
    'ж': 'ž',
    'з': 'z',
    'ѕ': 'dz',
    'и': 'i',
    'ы': 'i',
    'і': 'j',
    'ї': 'ji',
    'й': 'j',
    'ј': 'j',
    'к': 'k',
    'л': 'l',
    'љ': 'lj',
    'м': 'm',
    'н': 'n',
    'њ': 'nj',
    'о': 'o',
    'п': 'p',
    'р': 'r',
    'с': 's',
    'т': 't',
    'ћ': 'ć',
    'ќ': 'ć',
    'у': 'u',
    'ф': 'f',
    'х': 'h',
    'ц': 'c',
    'ч': 'č',
    'џ': 'dž',
    'ш': 'š',
    'щ': 'šć',
    'ю': 'ju',
    'я': 'ja',
    'ъ': '',
    'ь': '',
  };
  final buf = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    buf.write(map[text[i]] ?? text[i]);
  }
  return buf.toString();
}

/// Heuristički parser teksta sa srpskih računa i uplatnica (za lokalni OCR i clipboard).
///
/// Primenjuje strogi "Confidence Gate": vraća [InvoiceData] isključivo kada su:
/// 1. Broj računa (18 cifara) matematički validan po Modulo-97 algoritmu,
/// 2. Naziv primaoca pronađen (min 3 karaktera),
/// 3. Poziv na broj validan (posebno Modulo-97 ako je na računu detektovan model 97).
/// Iznos ako nije pronađen u tekstu ostaje 0 (korisnik ga unosi ručno u formi).
///
/// Ako bilo koji od obaveznih uslova nije zadovoljen, vraća `null` kako bi obrada
/// bezbedno prešla na AI fallback.
InvoiceData? tryParseInvoiceText(
  String rawText, {
  String? horizontalRowsText,
}) {
  if (rawText.trim().isEmpty) return null;

  // 0. Ako tekst već sadrži sirovi NBS IPS QR string (npr. K:PR|V:01|...), parsiraj direktno.
  final ipsMatch = RegExp(
    r'K:(?:PR|EK)\|[^\r\n]+',
    caseSensitive: false,
  ).firstMatch(rawText);
  if (ipsMatch != null) {
    final direct = parseIpsString(ipsMatch.group(0)!);
    if (direct != null && validateAccountNumber(direct.accountNumber)) {
      return direct;
    }
  }

  final latinText = cyrillicToLatin(rawText);
  final normalizedText = latinText
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');
  final lines = normalizedText
      .split('\n')
      .map((l) => l.replaceAll(RegExp(r'[|\[\]_~]'), ' ').trim())
      .where((l) => l.isNotEmpty)
      .toList();
  if (lines.isEmpty) return null;

  final horizontalLatin =
      horizontalRowsText != null && horizontalRowsText.trim().isNotEmpty
      ? cyrillicToLatin(
          horizontalRowsText,
        ).replaceAll('\r\n', '\n').replaceAll('\r', '\n')
      : null;
  final horizontalLines = horizontalLatin != null
      ? horizontalLatin
            .split('\n')
            .map((l) => l.replaceAll(RegExp(r'[|\[\]_~]'), ' ').trim())
            .where((l) => l.isNotEmpty)
            .toList()
      : const <String>[];

  // 1. Broj računa (mora proći Modulo-97).
  final accountNumber =
      _extractValidAccountNumber(normalizedText, lines) ??
      (horizontalLatin != null
          ? _extractValidAccountNumber(horizontalLatin, horizontalLines)
          : null);
  if (accountNumber == null || !validateAccountNumber(accountNumber)) {
    return null;
  }

  // 2. Iznos: ako je prepoznat koristi se, inače 0 (korisnik unosi u formi).
  final amountLines = horizontalLines.isEmpty
      ? lines
      : <String>[...lines, ...horizontalLines];
  final rawAmount = _extractAmount(normalizedText, amountLines);
  final amountResult = (rawAmount != null && rawAmount > 0) ? rawAmount : 0.0;

  // 3. Poziv na broj i model.
  var refResult = _extractReferenceNumber(normalizedText, lines);
  if ((!refResult.isReliable || refResult.value.isEmpty) &&
      horizontalLatin != null) {
    final horizRef = _extractReferenceNumber(horizontalLatin, horizontalLines);
    if (horizRef.isReliable && horizRef.value.isNotEmpty) {
      refResult = horizRef;
    }
  }
  if (!refResult.isReliable) {
    return null;
  }

  // 4. Primalac.
  final recipientName =
      _extractRecipientName(lines, accountNumber) ??
      (horizontalLines.isNotEmpty
          ? _extractRecipientName(horizontalLines, accountNumber)
          : null);
  if (recipientName == null || recipientName.trim().length < 3) {
    return null;
  }

  // 5. Šifra plaćanja i svrha uplate.
  final paymentCode = _extractPaymentCode(
    horizontalLines.isEmpty ? lines : <String>[...lines, ...horizontalLines],
  );
  final purpose =
      _extractPurpose(lines) ??
      (horizontalLines.isNotEmpty ? _extractPurpose(horizontalLines) : null) ??
      'Uplata po računu';

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
  final dashedRegex = RegExp(
    r'\b(\d{3})\s*[-–—]\s*(\d{1,13})\s*[-–—]\s*(\d{2})\b',
  );
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
          context.contains('broj računa') ||
          context.contains('račun')) {
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

  // Srpski format iznosa sa 2 decimale: npr. = 1.234,56 ili 12.345,67 ili 450,00
  // (ili 3.522.54 ili 3522. 54 kada OCR pročita decimalni zarez kao tačku sa razmakom).
  // Lookaround sprečava da se deo datuma ("21.10.2026" → 21,10), dužeg broja,
  // negativna vrednost ("-24,62") ili procenat ("77,06 %") pročita kao iznos.
  final amountRegex = RegExp(
    r'(?:=\s*)?(?<![\d.,\-])(\d{1,3}(?:[.\s]\d{3})+\s*[.,]\s*\d{2}|\d+\s*[.,]\s*\d{2})(?![.,]?\d|\s*%)',
  );

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final lower = line.toLowerCase();
    final prevLower = i > 0 ? lines[i - 1].toLowerCase() : '';
    final nextLower = i + 1 < lines.length ? lines[i + 1].toLowerCase() : '';
    // OCR po kolonama često vrati vrednost pre labele ("400,00" pa "Ukupno za
    // uplatu:"), pa se ključne reči traže i u sledećoj liniji — ali samo ako je
    // ona čista labela, a ne rečenica sa sopstvenim iznosom.
    final nextIsLabel =
        i + 1 < lines.length && !amountRegex.hasMatch(lines[i + 1]);
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
      const topPhrases = [
        'ukupno za uplatu',
        'iznos za uplatu',
        'svega za uplatu',
        'za uplatu',
        'za uplatiti',
        'za plaćanje',
        'za placanje',
        'uplatom od',
        'uplata od',
      ];
      final hasInlineTopPhrase = _containsAny(lower, topPhrases);
      final isDiscountDeadline =
          !_containsAny(lower, const ['uplatom od', 'uplata od']) &&
          RegExp(r'za\s+uplatu\s+do\s+\d').hasMatch(context);

      if (!isDiscountDeadline && _containsAny(context, topPhrases)) {
        score += 100;
        if (hasInlineTopPhrase) {
          score += 35;
        }
      } else if (_containsAny(lower, const ['ukupno']) &&
          _containsAny(lower, const ['zaduženje', 'zaduzenje'])) {
        score += 85;
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
      if (isDiscountDeadline ||
          (_containsAny(lower, const [
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
              ]))) {
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
  final cleaned = raw.trim().replaceAll(' ', '');
  if (cleaned.contains(',')) {
    // Format 1.234,56 -> ukloni tačke i zameni zarez tačkom
    final normalized = cleaned.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(normalized);
  } else {
    // Format 1234.56 ili 3.522.54 (kada OCR pročita decimalni zarez kao tačku)
    final lastDot = cleaned.lastIndexOf('.');
    if (lastDot > 0 && cleaned.indexOf('.') != lastDot) {
      final intPart = cleaned.substring(0, lastDot).replaceAll('.', '');
      final decPart = cleaned.substring(lastDot + 1);
      return double.tryParse('$intPart.$decPart');
    }
    return double.tryParse(cleaned);
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
    'poziv na br',
    'odobrenje',
    'model',
  ]);
  final hasStandalone97 = lines.any((l) => l.trim() == '97');
  final mentionsModel97 =
      hasStandalone97 ||
      RegExp(
        r'model[a-z\s:.\-]{0,20}\b97\b|\b97\s+\d{2}[-\s]?\d{3,}',
        caseSensitive: false,
      ).hasMatch(fullText);

  // 1. Pokušaj pronalaska eksplicitnog Modela 97 + poziva na broj koji prolazi Modulo-97
  final mod97Candidates = <String>[];

  void tryAddMod97Token(String rawToken, {required bool allowPrepend97}) {
    final trimmed = rawToken.trim();
    final cleanDigits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanDigits.length == 18 && validateAccountNumber(cleanDigits)) {
      return; // Preskoči 18-cifreni broj računa
    }
    final clean = trimmed.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    if (clean.startsWith('97') &&
        clean.length >= 6 &&
        clean.length <= IpsLimits.ro &&
        validateReferenceNumber(clean)) {
      mod97Candidates.add(clean);
    } else if (allowPrepend97) {
      final with97 = '97$clean';
      if (with97.length >= 6 &&
          with97.length <= IpsLimits.ro &&
          validateReferenceNumber(with97)) {
        mod97Candidates.add(with97);
      }
    }
  }

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
      tryAddMod97Token('97$tail', allowPrepend97: false);
    }

    // Ako linija spominje "poziv na broj", "model" ili "račun primaoca", proveri
    // okolne linije (na uplatnicama je poziv na broj često odmah ispod broja računa).
    final lower = line.toLowerCase();
    if (_containsAny(lower, const [
      'poziv na broj',
      'poziv na br',
      'odobrenje',
      'model',
      'račun primaoca',
      'racun primaoca',
      'tekući račun',
      'tekuci racun',
    ])) {
      final startIdx = i >= 3 ? i - 3 : 0;
      final endIdx = i + 5 < lines.length ? i + 5 : lines.length - 1;
      final window = [
        for (var k = startIdx; k <= endIdx; k++) lines[k],
      ].join(' ');

      final tokenRegex = RegExp(r'\b([0-9]{2}[-\s]?[0-9A-Z][0-9A-Z-]{3,22})\b');
      for (final m in tokenRegex.allMatches(window)) {
        tryAddMod97Token(m.group(1)!, allowPrepend97: mentionsModel97);
      }
    }
  }

  // Fallback za Model 97: ako je na uplatnici prisutan broj 97 ili višedelni
  // poziv sa crticama, proveri kandidate sa crticama koji matematički prolaze Modulo-97 kontrolu.
  if (mod97Candidates.isEmpty) {
    final dashedRefRegex = RegExp(
      r'\b([0-9]{2}-[0-9A-Z][0-9A-Z-]{4,22})\b',
      caseSensitive: false,
    );
    for (final line in lines) {
      for (final m in dashedRefRegex.allMatches(line)) {
        final token = m.group(1)!;
        final hasMultipleDashes = '-'.allMatches(token).length >= 2;
        if (mentionsModel97 || hasMultipleDashes) {
          tryAddMod97Token(token, allowPrepend97: true);
        }
      }
    }
  }

  if (mod97Candidates.isNotEmpty) {
    return _RefExtraction(mod97Candidates.first, isReliable: true);
  }

  // Ako račun eksplicitno zahteva Model 97, a nismo našli validan Mod97 poziv na broj,
  // ne smemo nagađati — prepusti AI fallback-u.
  if (mentionsModel97) {
    return const _RefExtraction('', isReliable: false);
  }

  // 2. Model 00 ili poziv na broj bez modela 97
  for (var i = 0; i < lines.length; i++) {
    final lower = lines[i].toLowerCase();
    if (_containsAny(lower, const ['poziv na broj', 'poziv na br', 'odobrenje'])) {
      final searchLines = [
        lines[i],
        for (var k = i + 1; k <= i + 3 && k < lines.length; k++)
          if (!RegExp(r'[a-zčćžšđ:]').hasMatch(lines[k])) lines[k],
      ];
      for (final sLine in searchLines) {
        final cleanedLine = sLine.replaceFirst(
          RegExp(
            r'^.*?(?:poziv na broj|poziv na br\S*|odobrenje)\s*[():\-]*\s*',
            caseSensitive: false,
          ),
          '',
        );
        final m = RegExp(
          r'\b(?:00[\s-]*)?([0-9][0-9A-Z-]{3,22})\b',
        ).firstMatch(cleanedLine);
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

  if (mentionsRefOrModel) {
    return const _RefExtraction('', isReliable: false);
  }

  return const _RefExtraction('', isReliable: true);
}

final _purposeLabelRegex = RegExp(
  r's[vuao]rha\s+(?:uplate|pla[ćc]anja)',
  caseSensitive: false,
);
/// Opšte pravne forme i tipovi javnih ustanova u Srbiji (bez hardkodovanih naziva firmi).
final _entityRegex = RegExp(
  r'\b(J\.?K\.?P\.?|J\.?P\.?|D\.?O\.?O\.?|A\.?D\.?|K\.?D\.?|O\.D\.|P\.R\.|AKCIONARSKO\s+DRU[ŠS]TVO|JAVNO\s+(?:KOMUNALNO\s+)?PREDUZE[ĆC]E|DRU[ŠS]TVO\s+SA\s+OGRANI[ČC]ENOM|KOMANDITNO\s+DRU[ŠS]TVO|ORTA[ČC]KO\s+DRU[ŠS]TVO|PREDUZETNIK|UPRAVA|MINISTARSTVO|USTANOVA|ZAJEDNICA|ZAVOD|FOND\b|UDRU[ŽZ]ENJE|SAVEZ)\b',
  caseSensitive: false,
);

/// Imena platioca: prva ne-labela ispod svake labele "Platilac"/"Uplatilac".
Set<String> _payerNames(List<String> lines) {
  final names = <String>{};
  for (var i = 0; i < lines.length; i++) {
    final lower = lines[i].toLowerCase();
    if (!lower.startsWith('platilac') && !lower.startsWith('uplatilac')) {
      continue;
    }
    for (var k = i + 1; k <= i + 3 && k < lines.length; k++) {
      final candidate = lines[k].split('   ').first.trim();
      final candLower = candidate.toLowerCase();
      if (candLower.endsWith(':') || candLower.startsWith('primalac')) break;
      if (_isLabelOrNoise(candidate)) continue;
      names.add(candLower);
      break;
    }
  }
  return names;
}

/// Izvlači naziv primaoca iz linija oko labele "Primalac", strukture uplatnice ili pravne forme.
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
      final leftCell = line.split('   ').first;
      final inline = leftCell
          .replaceFirst(
            RegExp(
              r'^.*?(?:naziv primaoca|primalac|prodavac|izdavalac(?:\s+računa)?)\s*[:\-]\s*',
              caseSensitive: false,
            ),
            '',
          )
          .trim();
      if (inline.length >= 3 &&
          inline.toLowerCase() != leftCell.toLowerCase() &&
          !_isLabelOrNoise(inline)) {
        return inline;
      }

      // Naziv je u sledećim linijama ispod labele "Primalac".
      final candidates = <String>[];
      for (var offset = 1; offset <= 4 && i + offset < lines.length; offset++) {
        final candidate = lines[i + offset].split('   ').first.trim();
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

  // 2. Strukturni fallback na srpskoj uplatnici kada je sitna labela "Primalac:"
  // oštećena na slici: u levoj koloni uplatnice polje Primalac se nalazi odmah
  // ispod polja "Svrha uplate:" + 1 linije svrhe, i prati ga poštanski broj + mesto.
  final postalCityRegex = RegExp(r'^\d{5}\s+[A-Za-zČĆŽŠĐčćžšđ]{3,}');
  for (var i = 0; i < lines.length; i++) {
    final lower = lines[i].toLowerCase();
    if (_purposeLabelRegex.hasMatch(lower)) {
      final leftCell = lines[i].split('   ').first;
      final hasInlinePurpose = leftCell
              .replaceFirst(
                RegExp(
                  r'^.*?s[vuao]rha\s+(?:uplate|pla[ćc]anja)\s*[:\-]?\s*',
                  caseSensitive: false,
                ),
                '',
              )
              .trim()
              .length >=
          3;
      final startOffset = hasInlinePurpose ? 1 : 2;
      for (
        var offset = startOffset;
        offset <= startOffset + 3 && i + offset < lines.length;
        offset++
      ) {
        final candidate = lines[i + offset].split('   ').first.trim();
        if (_isLabelOrNoise(candidate) ||
            payers.contains(candidate.toLowerCase()) ||
            postalCityRegex.hasMatch(candidate)) {
          continue;
        }
        final nextLine = i + offset + 1 < lines.length
            ? lines[i + offset + 1].split('   ').first.trim()
            : '';
        if (postalCityRegex.hasMatch(nextLine) ||
            _entityRegex.hasMatch(candidate)) {
          return candidate;
        }
      }
    }
  }

  // 3. Fallback: Prepoznaj liniju sa opštom pravnom formom (DOO, AD, JKP, JP...)
  for (final line in lines) {
    final candidate = line.split('   ').first.trim();
    if (_entityRegex.hasMatch(candidate) &&
        candidate.length >= 4 &&
        candidate.length <= 80 &&
        !_isLabelOrNoise(candidate)) {
      return candidate;
    }
  }

  return null;
}

/// Izvlači svrhu uplate ako je prisutna.
String? _extractPurpose(List<String> lines) {
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final lower = line.toLowerCase();
    if (_purposeLabelRegex.hasMatch(lower)) {
      final leftCell = line.split('   ').first;
      final inline = leftCell
          .replaceFirst(
            RegExp(
              r'^.*?s[vuao]rha\s+(?:uplate|pla[ćc]anja)\s*[:\-]?\s*',
              caseSensitive: false,
            ),
            '',
          )
          .trim();
      if (inline.length >= 3 &&
          inline.toLowerCase() != leftCell.toLowerCase() &&
          !_isLabelOrNoise(inline)) {
        return inline;
      }
      for (var offset = 1; offset <= 4 && i + offset < lines.length; offset++) {
        final next = lines[i + offset].split('   ').first.trim();
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
    if (lower.contains('šifra') ||
        lower.contains('sifra') ||
        lower.contains('šif.') ||
        lower.contains('sif.')) {
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
  // Mašinski čitljiva OCR-B linija sa dna uplatnice (više dugih nizova cifara)
  if (RegExp(r'\d{7,}.*\d{7,}').hasMatch(lower)) return true;
  // Polja iz desne kolone uplatnice (šifra plaćanja, šifra komitenata, model 97)
  if (RegExp(r'^(?:189|289|114|97)\b').hasMatch(lower)) return true;

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
  if (forbiddenExact.contains(lower) ||
      RegExp(
        r'^s[vuao]rha\s+(?:uplate|pla[ćc]anja)\s*[:\-]?$',
      ).hasMatch(lower)) {
    return true;
  }
  if (_containsAny(lower, const [
    'šif. pla',
    'sif. pla',
    'šif. kom',
    'sif. kom',
    'f. kom',
    'šifra plaćanja',
    'sifra placanja',
    'tekući račun',
    'tekuci racun',
    'račun primaoca',
    'racun primaoca',
    'broj modela',
    'poziv na broj',
  ])) {
    return true;
  }
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
