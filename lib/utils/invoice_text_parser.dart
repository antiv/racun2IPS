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
    ('АЬ', 'ANJ'),
    ('Аь', 'Anj'),
    ('аь', 'anj'),
    ('ЕЬ', 'ENJ'),
    ('Еь', 'Enj'),
    ('еь', 'enj'),
    ('ИЬ', 'INJ'),
    ('Иь', 'Inj'),
    ('иь', 'inj'),
    ('ОЬ', 'ONJ'),
    ('Оь', 'Onj'),
    ('оь', 'onj'),
    ('УЬ', 'UNJ'),
    ('Уь', 'Unj'),
    ('уь', 'unj'),
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
  final isUpperLetter = RegExp(r'[А-ЯЂЈЉЊЋЏA-ZČĆŽŠĐ]');
  final isLowerLetter = RegExp(r'[а-яђјљњћџa-zčćžšđ]');
  const titleDigraphChars = {'Љ': 'LJ', 'Њ': 'NJ', 'Џ': 'DŽ'};

  final buf = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    final upperPair = titleDigraphChars[ch];
    if (upperPair != null) {
      final prevIsUpper = i > 0 && isUpperLetter.hasMatch(text[i - 1]);
      final nextIsUpper =
          i + 1 < text.length && isUpperLetter.hasMatch(text[i + 1]);
      final nextIsLower =
          i + 1 < text.length && isLowerLetter.hasMatch(text[i + 1]);
      if ((prevIsUpper || nextIsUpper) && !nextIsLower) {
        buf.write(upperPair);
        continue;
      }
    }
    buf.write(map[ch] ?? ch);
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
  String? numericFallbackText,
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
      .map((l) => l.trim())
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
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList()
      : const <String>[];

  final numFallbackLatin =
      numericFallbackText != null && numericFallbackText.trim().isNotEmpty
      ? cyrillicToLatin(
          numericFallbackText,
        ).replaceAll('\r\n', '\n').replaceAll('\r', '\n')
      : null;
  final numFallbackLines = numFallbackLatin != null
      ? numFallbackLatin
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList()
      : const <String>[];

  // 1. Broj računa (mora proći Modulo-97).
  final accountNumber =
      _extractValidAccountNumber(normalizedText, lines) ??
      (horizontalLatin != null
          ? _extractValidAccountNumber(horizontalLatin, horizontalLines)
          : null) ??
      (numFallbackLatin != null
          ? _extractValidAccountNumber(numFallbackLatin, numFallbackLines)
          : null);
  if (accountNumber == null || !validateAccountNumber(accountNumber)) {
    return null;
  }

  // 2. Iznos: ako je prepoznat koristi se, inače 0 (korisnik unosi u formi).
  final amountLines = <String>[
    ...lines,
    ...horizontalLines,
    ...numFallbackLines,
  ];
  final rawAmount = _extractAmount(normalizedText, amountLines);
  final amountResult = (rawAmount != null && rawAmount > 0) ? rawAmount : 0.0;

  // 3. Poziv na broj i model (Modulo-97 verifikovani "97..." uvek ima prednost nad "00...").
  final primaryMentionsModel97 =
      _detectModel97Mention(normalizedText, lines) ||
      (horizontalLatin != null &&
          _detectModel97Mention(horizontalLatin, horizontalLines));
  final primaryMentionsRef =
      _detectRefMention(normalizedText) ||
      (horizontalLatin != null && _detectRefMention(horizontalLatin));
  var refResult = _extractReferenceNumber(normalizedText, lines);
  if ((!refResult.isReliable ||
          refResult.value.isEmpty ||
          !refResult.value.startsWith('97')) &&
      horizontalLatin != null) {
    final horizRef = _extractReferenceNumber(horizontalLatin, horizontalLines);
    if (horizRef.isReliable &&
        horizRef.value.isNotEmpty &&
        (!refResult.isReliable ||
            refResult.value.isEmpty ||
            horizRef.value.startsWith('97'))) {
      refResult = horizRef;
    }
  }
  if ((!refResult.isReliable ||
          refResult.value.isEmpty ||
          !refResult.value.startsWith('97')) &&
      numFallbackLatin != null) {
    final numRef = _extractReferenceNumber(
      numFallbackLatin,
      numFallbackLines,
      hintModel97: primaryMentionsModel97 || primaryMentionsRef,
    );
    if (numRef.isReliable &&
        numRef.value.isNotEmpty &&
        (!refResult.isReliable ||
            refResult.value.isEmpty ||
            numRef.value.startsWith('97'))) {
      refResult = numRef;
    }
  }
  if (!refResult.isReliable) {
    return null;
  }

  // 4. Primalac (isključivo iz primarnog teksta, bez mešanja sa numeričkim fallback-om).
  final recipientName =
      _extractRecipientName(lines, accountNumber) ??
      (horizontalLines.isNotEmpty
          ? _extractRecipientName(horizontalLines, accountNumber)
          : null);
  if (recipientName == null || recipientName.trim().length < 3) {
    return null;
  }

  // 5. Šifra plaćanja i svrha uplate.
  final paymentCode = _extractPaymentCode(<String>[
    ...lines,
    ...horizontalLines,
    ...numFallbackLines,
  ]);
  final purpose =
      _extractPurpose(lines, recipientName: recipientName) ??
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

  // Regex 1: Format sa crticama ili razmacima kada kamera izostavi jednu ili obe crtice
  // (npr. 840-0000711171843-84, 160 - 123456 - 78, 200 75409 96, 20075409-96 ili 200-7540996)
  final dashedRegex = RegExp(
    r'(?<!\d)(\d{3})\s*[-–—._/]\s*(\d{1,13})\s*[-–—._/]\s*(\d{2})(?!\d)',
  );
  final spacedAccountRegex = RegExp(
    r'(?<!\d)(\d{3})[\s\-–—._/]+(\d{4,13})[\s\-–—._/]+(\d{2})(?!\d)',
  );
  final singleDashLeftRegex = RegExp(
    r'(?<!\d)(\d{3})\s*[-–—]\s*(\d{4,13})(\d{2})(?!\d)',
  );
  final singleDashRightRegex = RegExp(
    r'(?<!\d)(\d{3})(\d{4,13})\s*[-–—]\s*(\d{2})(?!\d)',
  );
  // Regex 2: Neprekidni niz od 18 cifara
  final flatRegex = RegExp(r'(?<!\d)(\d{18})(?!\d)');

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
    for (final m in spacedAccountRegex.allMatches(line)) {
      evaluateRaw('${m.group(1)}-${m.group(2)}-${m.group(3)}', 10);
    }
    for (final m in singleDashLeftRegex.allMatches(line)) {
      evaluateRaw('${m.group(1)}-${m.group(2)}-${m.group(3)}', 5);
    }
    for (final m in singleDashRightRegex.allMatches(line)) {
      evaluateRaw('${m.group(1)}-${m.group(2)}-${m.group(3)}', 5);
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

  // Kada ćirilični OCR pročita vodeću cifru '3' u iznosu (npr. "3.522,54") kao
  // ćirilično slovo 'З'/'з' ili 'у' (koje postaje 'Z'/'z'/'u' u latinici, npr. "u522,54"),
  // vraćamo cifru '3' ispred trocifrenog bloka i 2 decimale.
  final leadingThreeOcrRegex = RegExp(
    r'(?<![\p{L}\p{N}])[zZuU]\.?(\d{3}\s*[.,]\s*\d{2})\b',
    unicode: true,
  );

  // Srpski format iznosa sa 2 decimale: npr. = 1.234,56 ili 12.345,67 ili 450,00
  // (ili 3.522.54 ili 3522. 54 kada OCR pročita decimalni zarez kao tačku sa razmakom).
  // Lookaround sprečava da se deo datuma ("21.10.2026" → 21,10), dužeg broja,
  // negativna vrednost ("-24,62") ili procenat ("77,06 %") pročita kao iznos.
  final amountRegex = RegExp(
    r'(?:=\s*)?(?<![\d.,\-])(\d{1,3}(?:[.\s]\d{3})+\s*[.,]\s*\d{2}|\d+\s*[.,]\s*\d{2})(?![.,]?\d|\s*%)',
  );

  // Mašinski čitljiva OCR-B linija sa dna uplatnice često sadrži tačan iznos
  // u parama sa водеćim nulama (npr. "00000352254" -> 3522,54).
  final ocrBAmountCents = <int>{};
  final ocrBRegex = RegExp(r'\b0{4,7}([1-9]\d{3,8})\b');
  for (final l in lines) {
    for (final m in ocrBRegex.allMatches(l)) {
      final val = int.tryParse(m.group(1)!);
      if (val != null && val > 100) {
        ocrBAmountCents.add(val);
      }
    }
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].replaceAllMapped(
      leadingThreeOcrRegex,
      (m) => '3.${m.group(1)!}',
    );
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

      // Ako se kandidat poklapa sa iznosom u parama iz OCR-B linije uplatnice
      if (ocrBAmountCents.contains((parsed * 100).round())) {
        score += 65;
      }

      candidates.add(_ScoredCandidate(parsed, score));
    }

    // Ako je na liniji sa "ZA UPLATU" ili u OCR-B liniji decimalni zarez izostao
    // zbog niske rezolucije kamere (npr. "352254" umesto "3.522,54"), a broj
    // je potvrđen u OCR-B liniji uplatnice, dodaj ga kao kandidata.
    if (ocrBAmountCents.isNotEmpty) {
      for (final m in RegExp(r'\b([1-9]\d{4,7})\b').allMatches(line)) {
        final cents = int.tryParse(m.group(1)!);
        if (cents != null && ocrBAmountCents.contains(cents)) {
          candidates.add(_ScoredCandidate(cents / 100.0, 120));
        }
      }
    }
  }

  if (candidates.isEmpty) return null;

  // Ako se isti iznos sa pozitivnim kontekstom (score >= 50) pojavljuje više puta
  // na računu (npr. u tabeli "ZA UPLATU", u "Uplatom od..." i na talonu),
  // dodaj bonus za konzistentnost kako pojedinačna OCR greška ne bi prevagnula.
  final freqByAmount = <int, int>{};
  for (final c in candidates) {
    if (c.score >= 50) {
      final cents = (c.value * 100).round();
      freqByAmount[cents] = (freqByAmount[cents] ?? 0) + 1;
    }
  }
  final boosted = [
    for (final c in candidates)
      _ScoredCandidate(
        c.value,
        c.score +
            ((c.score >= 50 &&
                    (freqByAmount[(c.value * 100).round()] ?? 0) >= 2)
                ? 35
                : 0),
      ),
  ]..sort((a, b) => b.score.compareTo(a.score));

  // Confidence Gate: prihvatamo samo iznos koji ima jasnu kontekstualnu potvrdu
  if (boosted.first.score < 50) return null;
  return boosted.first.value;
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

bool _detectRefMention(String fullText) {
  return _containsAny(fullText.toLowerCase(), const [
    'poziv na broj',
    'poziv na br',
    'odobrenje',
    'model',
  ]);
}

bool _detectModel97Mention(String fullText, List<String> lines) {
  final hasStandalone97 = lines.any(
    (l) =>
        RegExp(r'^[^\p{L}\p{N}]*97[^\p{L}\p{N}]*$', unicode: true).hasMatch(l),
  );
  return hasStandalone97 ||
      RegExp(
        r'model[a-z\s:.\-]{0,20}\b97\b|\b97\s+\d{2}[-\s]?\d{3,}',
        caseSensitive: false,
      ).hasMatch(fullText);
}

/// Izvlači model i poziv na broj, uz proveru Modulo-97 kada je prisutan model 97.
_RefExtraction _extractReferenceNumber(
  String fullText,
  List<String> lines, {
  bool hintModel97 = false,
}) {
  final lowerFull = fullText.toLowerCase();
  final mentionsRefOrModel = _containsAny(lowerFull, const [
    'poziv na broj',
    'poziv na br',
    'odobrenje',
    'model',
  ]);
  final mentionsModel97 = hintModel97 || _detectModel97Mention(fullText, lines);

  // 1. Pokušaj pronalaska eksplicitnog Modela 97 + poziva na broj koji prolazi Modulo-97
  final mod97Candidates = <String>[];

  void tryAddSingleMod97(String candidate, {required bool allowPrepend97}) {
    final cleanDigits = candidate.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanDigits.length == 18 && validateAccountNumber(cleanDigits)) {
      return; // Preskoči 18-cifreni broj računa
    }
    final clean = candidate
        .replaceAll(RegExp(r'[\s\-–—._/]'), '')
        .toUpperCase();
    if (clean.startsWith('97') &&
        clean.length >= 6 &&
        clean.length <= IpsLimits.ro &&
        validateReferenceNumber(clean)) {
      mod97Candidates.add(clean);
      return;
    }
    if (allowPrepend97) {
      final with97 = '97$clean';
      if (with97.length >= 6 &&
          with97.length <= IpsLimits.ro &&
          validateReferenceNumber(with97)) {
        mod97Candidates.add(with97);
        return;
      }
      // Ako je vertikalna linija okvira boksa pročitana kao vodeće/prateće 'I' ili 'l'
      final strippedBorder = clean.replaceAll(RegExp(r'^[IL]|[IL]$'), '');
      if (strippedBorder != clean) {
        final with97Border = '97$strippedBorder';
        if (with97Border.length >= 6 &&
            with97Border.length <= IpsLimits.ro &&
            validateReferenceNumber(with97Border)) {
          mod97Candidates.add(with97Border);
        }
      }
    }
  }

  void tryAddMod97Token(String rawToken, {required bool allowPrepend97}) {
    final trimmed = rawToken.trim();
    if (trimmed.isEmpty) return;
    // Ako je regex uhvatio i reč/broj iz sledeće kolone ili reda (razdvojeno razmakom),
    // isprobaj prvo kraće prefikse bez pratećih reči, pa ceo niz.
    final parts = trimmed.split(RegExp(r'\s+'));
    final acc = StringBuffer();
    for (var p = 0; p < parts.length; p++) {
      if (p > 0) acc.write(' ');
      acc.write(parts[p]);
      tryAddSingleMod97(acc.toString(), allowPrepend97: allowPrepend97);
    }
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final nextLine = i + 1 < lines.length ? lines[i + 1] : '';
    final combined = '$line   $nextLine';

    // Traži patern: "97" praćen kontrolnim brojem i pozivom (sa razmacima/crticama),
    // uključujući OCR-B liniju gde je 3-cifrena šifra plaćanja (npr. 189/289) spojena ispred 97.
    final mod97Regex = RegExp(
      r'(?:^|\b|[12]\d{2})97[\s-]*([0-9]{2}[\s-]*[0-9A-Z][0-9A-Z\s-]{3,22})',
      caseSensitive: false,
    );
    for (final m in mod97Regex.allMatches(combined)) {
      tryAddMod97Token(m.group(1)!, allowPrepend97: true);
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
      final tokenRegex = RegExp(
        r'(?<!\d)([0-9]{2}[-\s]*[0-9A-Z][0-9A-Z\s-]{3,24})',
      );
      for (var k = startIdx; k <= endIdx; k++) {
        for (final cell in lines[k].split('   ')) {
          for (final m in tokenRegex.allMatches(cell)) {
            tryAddMod97Token(m.group(1)!, allowPrepend97: true);
          }
        }
      }
    }
  }

  // Fallback za Model 97: ako je na uplatnici prisutan broj 97 ili višedelni/duži
  // poziv sa crticama (uključujući slučaj kad OCR izostavi prvu crticu, npr.
  // "1402004377503-2610"), proveri kandidate koji matematički prolaze Modulo-97.
  if (mod97Candidates.isEmpty) {
    final dashedRefRegex = RegExp(
      hintModel97
          ? r'(?<!\d)([0-9]{2}[0-9A-Z\s\-–—._/]{5,24})'
          : r'(?<!\d)([0-9]{2}[0-9A-Z\s-]*-[0-9A-Z\s-]{3,24})',
      caseSensitive: false,
    );
    for (final line in lines) {
      for (final cell in line.split('   ')) {
        for (final m in dashedRefRegex.allMatches(cell)) {
          final token = m.group(1)!;
          final compactLen = token.replaceAll(RegExp(r'[^0-9A-Z]', caseSensitive: false), '').length;
          final hasMultipleDashes = '-'.allMatches(token).length >= 2;
          final isLongDashed = token.contains('-') && compactLen >= 9;
          if (mentionsModel97 ||
              mentionsRefOrModel ||
              hasMultipleDashes ||
              isLongDashed ||
              (hintModel97 && compactLen >= 9)) {
            tryAddMod97Token(token, allowPrepend97: true);
          }
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
    if (_containsAny(lower, const [
      'poziv na broj',
      'poziv na br',
      'odobrenje',
    ])) {
      final searchLines = [
        lines[i],
        for (var k = i + 1; k <= i + 3 && k < lines.length; k++)
          if (!RegExp(
            r'[a-zčćžšđ:]|\b(?:KW|KWH|RSD|DIN|M3)\b',
          ).hasMatch(lines[k]))
            lines[k],
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
          // Višedelni poziv oblika "KK-broj-period" (2 cifre + 5+ cifara + 2+ cifre)
          // koji nije prošao Modulo-97 u koraku 1 je oštećen Model 97 broj, ne Model 00.
          if (RegExp(r'^\d{2}-\d{5,}-\d{2,}$').hasMatch(token.trim())) {
            continue;
          }
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
  r'\b(?:(?:[sc]|lj)[vuao]?r[hknažz]a\s+(?:up[l1iunp]at[esao]|p[l1iunp]a[ćčc]a(?:nja|na|a)?)|svrha\s*[:\-])',
  caseSensitive: false,
);

final _recipientLabelRegex = RegExp(
  r'\b(?:naziv\s+primao[cč]a|[pt]?r[iein]m[ae][lpn]a[cčidžou]?|[pt]?r[iein]mala|prodavac|izdavalac(?:\s+ra[čc]una)?)\b',
  caseSensitive: false,
);

final _payerLabelRegex = RegExp(
  r'^[^\p{L}\p{N}]*(?:u?p[l1i]?at[inml1p][l1i]a[cčdžo]?)\b',
  caseSensitive: false,
  unicode: true,
);

final _accountFieldLabelRegex = RegExp(
  r'(?:ra[čc]un\s+primao[cč]a|teku[ćc]i\s+ra[čc]un|[žz]iro\s+ra[čc]un|uplatni\s+ra[čc]un)',
  caseSensitive: false,
);

/// Uklanja labele i vrednosti desne kolone uplatnice ako su u OCR-u spojene
/// u isti red sa tekstom iz leve kolone (npr. "Уплата по рачуну Шиф. плаћ. 189").
final _rightColumnTailRegex = RegExp(
  r'\s+(?:[šs]if(?:ra|\.)\s*(?:pla[ćčc]|kom)|teku[ćc]i\s+ra[čc]un|ra[čc]un\s+primao[cč]a|broj\s+modela|poziv\s+na\s+br|valuta\s+rsd|iznos\b).*$',
  caseSensitive: false,
);

String _stripRightColumnTail(String text) {
  return text.replaceFirst(_rightColumnTailRegex, '').trim();
}

/// Opšte pravne forme i tipovi javnih ustanova u Srbiji (bez hardkodovanih naziva firmi).
/// Dvoslovne skraćenice bez tačaka (AD, Ad, JP, Jp) ne smeju biti u svim malim slovima
/// niti praćene poštanskim/kućnim brojem (kako prelomljeno "БЕОГР-ад 129"
/// u adresi platioca nikada ne bi bilo prepoznato kao pravna forma "AD").
final _unambiguousEntityRegex = RegExp(
  r'\b(J\.?K\.?P\.?|D\.?O\.?O\.?|A\.D\.?|J\.P\.?|K\.D\.|O\.D\.|P\.R\.|AKCIONARSKO\s+DRU[ŠS]TVO|JAVNO\s+(?:KOMUNALNO\s+)?PREDUZE[ĆC]E|DRU[ŠS]TVO\s+SA\s+OGRANI[ČC]ENOM|KOMANDITNO\s+DRU[ŠS]TVO|ORTA[ČC]KO\s+DRU[ŠS]TVO|PREDUZETNIK|UPRAVA|MINISTARSTVO|USTANOVA|STAMBENA\s+ZAJEDNICA|ZAJEDNICA|ZAVOD|FOND\b|UDRU[ŽZ]ENJE|SAVEZ)\b',
  caseSensitive: false,
);

final _upperShortEntityRegex = RegExp(
  r'\b(?:AD|Ad|JP|Jp)\b(?!\s*\d)',
);

final _postalCityRegex = RegExp(
  r'^\d{2,5}\s+[A-Za-zČĆŽŠĐčćžšđ]{2,}(?:\s+[A-Za-zČĆŽŠĐčćžšđ]{2,})?(?:\s+\d{1,3})?$',
);

final _fullSerbianPostalRegex = RegExp(
  r'^[123]\d{4}\s+[A-Za-zČĆŽŠĐčćžšđ]{3,}',
);

final _brokenPostalTailRegex = RegExp(
  r'(?:^\d{2,5}\s+[A-Za-zČĆŽŠĐčćžšđ]|\b(?:ad|a\.?d\.?|sad|grad|orad)\s+\d{1,3}\s*$)',
  caseSensitive: false,
);

bool _hasLegalEntityForm(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return false;
  if (_postalCityRegex.hasMatch(trimmed) ||
      _brokenPostalTailRegex.hasMatch(trimmed)) {
    return false;
  }
  return _unambiguousEntityRegex.hasMatch(trimmed) ||
      _upperShortEntityRegex.hasMatch(trimmed);
}

final _streetAddressRegex = RegExp(
  r'^(?:ul\.?\s+|ulica\s+|bul\.?\s+|bulevar\s+|trg\s+|dr\s+|kneza\s+|kralja\s+|cara\s+|vojvode\s+|generala\s+|[a-zčćžšđ\s]{4,}\s+\d+(?:[\/\-]\d+|\s*bb\b))',
  caseSensitive: false,
);

final _purposePhraseRegex = RegExp(
  r'^(?:u?p[l1i]ata\s+po\s+ra[čcćm]u[nm]u|ra[čc]un\s+za\s+|komunalne\s+usluge|utro[šs]ena\s+elektri[čc]na|mese[čc]ni\s+ra[čc]un|redovno\s+odr[žz]avanje)',
  caseSensitive: false,
);

final _damagedUplataPoRacunuRegex = RegExp(
  r'^(?:[uil1jptae]{1,4}|[a-zčćžšđ]{0,7}t[ae])\s+po\s+ra[čcćm]u[nm]u$',
  caseSensitive: false,
);

String _normalizeCommonPurpose(String text) {
  final cleaned = _cleanEntityName(text);
  if (_damagedUplataPoRacunuRegex.hasMatch(cleaned)) {
    return 'Uplata po računu';
  }
  return cleaned;
}

/// Proverava da li je [candidate] kvalitetnija (specifičnija) svrha uplate od [current].
bool isBetterPurpose(String candidate, {required String current}) {
  final candTrim = candidate.trim();
  if (candTrim.length < 3 || candTrim == 'Uplata po računu') return false;
  final currTrim = current.trim();
  return currTrim.isEmpty || currTrim == 'Uplata po računu';
}

/// Proverava da li je [candidate] potpuniji naziv primaoca od [current]
/// (npr. sadrži pravnu formu DOO/AD/JKP/JP koja je u drugom rasporedu izostala).
bool isBetterRecipientName(String candidate, {required String current}) {
  final candTrim = candidate.trim();
  if (candTrim.length < 3) return false;
  final currTrim = current.trim();
  if (currTrim.length < 3) return true;
  if (_hasLegalEntityForm(candTrim) && !_hasLegalEntityForm(currTrim)) {
    return true;
  }
  return false;
}

bool _isRecipientLabelLine(String line) {
  final leftPart = _stripRightColumnTail(line.split('   ').first).toLowerCase();
  return _recipientLabelRegex.hasMatch(leftPart) &&
      !_accountFieldLabelRegex.hasMatch(leftPart);
}

bool _isSectionBoundaryLabel(String text) {
  final lower = text.toLowerCase().trim();
  if (_payerLabelRegex.hasMatch(lower) ||
      _purposeLabelRegex.hasMatch(lower) ||
      _isRecipientLabelLine(lower) ||
      _accountFieldLabelRegex.hasMatch(lower)) {
    return true;
  }
  if (lower.startsWith('broj modela') ||
      lower.startsWith('poziv na') ||
      lower.startsWith('šifra plać') ||
      lower.startsWith('sifra plac') ||
      lower.startsWith('šif. plać') ||
      lower.startsWith('sif. plac')) {
    return true;
  }
  return false;
}

class _PayerInfo {
  const _PayerInfo(this.names, this.lineIndices);
  final Set<String> names;
  final Set<int> lineIndices;
}

/// Imena, redovi adrese i indeksi linija platioca ispod svake labele "Platilac"/"Uplatilac",
/// kako ulica ili grad platioca nikada ne bi bili pomešani sa primaocem ili svrhom.
_PayerInfo _extractPayerInfo(List<String> lines) {
  final names = <String>{};
  final indices = <int>{};
  for (var i = 0; i < lines.length; i++) {
    final leftCell = _stripRightColumnTail(lines[i].split('   ').first);
    if (!_payerLabelRegex.hasMatch(leftCell)) {
      continue;
    }
    indices.add(i);
    // Ako je ime platioca u istom redu sa labelom (npr. "ПЛАТИЛАЦ: АНТОНИЈЕВИЋ ИВАН")
    final inline = _cleanEntityName(
      leftCell.replaceFirst(
        RegExp(
          r'^[^\p{L}\p{N}]*(?:u?p?[l1i]?at[inml1p][l1i]a[cčdžo]?)\s*[:\-.;]*\s*',
          caseSensitive: false,
          unicode: true,
        ),
        '',
      ),
    );
    if (inline.length >= 3 &&
        inline.toLowerCase() != _cleanEntityName(leftCell).toLowerCase() &&
        !_isLabelOrNoise(inline) &&
        !_hasLegalEntityForm(inline)) {
      names.add(inline.toLowerCase());
    }

    var collected = 0;
    for (var k = i + 1; k <= i + 5 && k < lines.length; k++) {
      final candidate = _cleanEntityName(
        _stripRightColumnTail(lines[k].split('   ').first),
      );
      if (candidate.isEmpty) continue;
      final candLower = candidate.toLowerCase();
      if (_isSectionBoundaryLabel(candidate) || candLower.endsWith(':')) {
        break;
      }
      if (_isLabelOrNoise(candidate)) continue;
      // Pravna lica (DOO, AD, JKP, JP...) na računu su primaoci, ne fizičko lice platilac.
      if (_hasLegalEntityForm(candidate)) break;
      names.add(candLower);
      indices.add(k);
      collected++;
      // Posle poštanskog broja i grada adresa platioca je završena.
      if (_postalCityRegex.hasMatch(candidate) ||
          _brokenPostalTailRegex.hasMatch(candidate) ||
          _fullSerbianPostalRegex.hasMatch(candidate)) {
        break;
      }
      if (collected >= 4) break;
    }
  }
  return _PayerInfo(names, indices);
}

/// Izvlači naziv primaoca iz linija oko labele "Primalac", strukture uplatnice ili pravne forme.
String? _extractRecipientName(List<String> lines, String accountNumber) {
  final payerInfo = _extractPayerInfo(lines);
  final payers = payerInfo.names;
  final payerIndices = payerInfo.lineIndices;
  // 1. Traži eksplicitnu labelu "Primalac" (ali ne "Račun primaoca")
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (_isRecipientLabelLine(line)) {
      final leftCell = _stripRightColumnTail(line.split('   ').first);
      final inline = _cleanEntityName(
        leftCell.replaceFirst(
          RegExp(
            r'^.*?(?:naziv\s+primao[cč]a|p?r[iein]ma[lpi]a[cčidžou]|p?r[iein]mala|prodavac|izdavalac(?:\s+ra[čc]una)?)\s*[:\-.;]*\s*',
            caseSensitive: false,
          ),
          '',
        ),
      );
      if (inline.length >= 3 &&
          inline.toLowerCase() != _cleanEntityName(leftCell).toLowerCase() &&
          !_isLabelOrNoise(inline) &&
          !_isSectionBoundaryLabel(inline) &&
          !_purposePhraseRegex.hasMatch(inline) &&
          !_brokenPostalTailRegex.hasMatch(inline) &&
          !payers.contains(inline.toLowerCase())) {
        return inline;
      }

      // Naziv je u sledećim linijama ispod labele "Primalac".
      // U prirodnom Y-redosledu (fullText) linije desne kolone ("Tekući račun",
      // "Broj modela", "Poziv na broj") ili labela "Platilac:" desnog talona mogu
      // biti umetnute između labele "Primalac" i naziva primaoca, pa njih preskačemo
      // (`continue`), a prekidamo samo na novoj sekciji "Svrha uplate".
      final candidates = <String>[];
      for (var offset = 1; offset <= 10 && i + offset < lines.length; offset++) {
        if (payerIndices.contains(i + offset)) continue;
        final rawNext = _stripRightColumnTail(
          lines[i + offset].split('   ').first,
        );
        final candidate = _cleanEntityName(rawNext);
        if (candidate.isEmpty) continue;
        if (_purposeLabelRegex.hasMatch(candidate)) {
          break;
        }
        if (candidate.length >= 3 &&
            !_isLabelOrNoise(candidate) &&
            !_isSectionBoundaryLabel(candidate) &&
            !_postalCityRegex.hasMatch(candidate) &&
            !_brokenPostalTailRegex.hasMatch(candidate) &&
            !_purposePhraseRegex.hasMatch(candidate) &&
            !payers.contains(candidate.toLowerCase())) {
          candidates.add(candidate);
          if (candidates.length >= 3) break;
        }
      }
      if (candidates.isNotEmpty) {
        final entityIdx = candidates.indexWhere(_hasLegalEntityForm);
        if (entityIdx >= 0) {
          final primary = candidates[entityIdx];
          // Ako je naziv pravnog lica podeljen u 2 reda (npr. "PRVI PARTIZAN" pa "DOO UŽICE"),
          // spoji prvi red sa drugim ako prvi red nije ulica/adresa.
          if (entityIdx == 1 &&
              !_streetAddressRegex.hasMatch(candidates[0]) &&
              !RegExp(r'\d').hasMatch(candidates[0]) &&
              primary.length <= 28) {
            return _cleanEntityName('${candidates[0]} $primary');
          }
          return _cleanEntityName(primary);
        }
        final nonAddress = candidates.where(
          (c) =>
              !_streetAddressRegex.hasMatch(c) &&
              !_postalCityRegex.hasMatch(c) &&
              !_brokenPostalTailRegex.hasMatch(c),
        );
        if (nonAddress.isNotEmpty) {
          return _cleanEntityName(nonAddress.first);
        }
        return _cleanEntityName(candidates.first);
      }
    }
  }

  // 2. Strukturni fallback na srpskoj uplatnici kada je sitna labela "Primalac:"
  // oštećena na slici: u levoj koloni uplatnice polje Primalac se nalazi odmah
  // ispod polja "Svrha uplate:" + 1 linije svrhe, i prati ga poštanski broj + mesto.
  for (var i = 0; i < lines.length; i++) {
    final lower = lines[i].toLowerCase();
    if (_purposeLabelRegex.hasMatch(lower)) {
      final leftCell = _stripRightColumnTail(lines[i].split('   ').first);
      final hasInlinePurpose =
          _cleanEntityName(
            leftCell.replaceFirst(
              RegExp(
                r'^.*?(?:(?:[sc]|lj)[vuao]?r[hknažz]a\s+(?:up[l1iunp]at[esao]|p[l1iunp]a[ćčc]a(?:nja|na|a)?)|\bsvrha)\s*[:\-.;]*\s*',
                caseSensitive: false,
              ),
              '',
            ),
          ).length >=
          3;
      final startOffset = hasInlinePurpose ? 1 : 2;
      for (
        var offset = startOffset;
        offset <= startOffset + 3 && i + offset < lines.length;
        offset++
      ) {
        if (payerIndices.contains(i + offset)) continue;
        final candidate = _cleanEntityName(
          _stripRightColumnTail(lines[i + offset].split('   ').first),
        );
        if (_isLabelOrNoise(candidate) ||
            _isSectionBoundaryLabel(candidate) ||
            _purposePhraseRegex.hasMatch(candidate) ||
            payers.contains(candidate.toLowerCase()) ||
            _postalCityRegex.hasMatch(candidate) ||
            _brokenPostalTailRegex.hasMatch(candidate)) {
          continue;
        }
        final nextLine = i + offset + 1 < lines.length
            ? _cleanEntityName(
                _stripRightColumnTail(lines[i + offset + 1].split('   ').first),
              )
            : '';
        if (_postalCityRegex.hasMatch(nextLine) ||
            _hasLegalEntityForm(candidate)) {
          return candidate;
        }
      }
    }
  }

  // 3. Fallback: Prepoznaj liniju sa opštom pravnom formom (DOO, AD, JKP, JP...)
  for (var i = 0; i < lines.length; i++) {
    if (payerIndices.contains(i)) continue;
    final candidate = _cleanEntityName(
      _stripRightColumnTail(lines[i].split('   ').first),
    );
    if (_hasLegalEntityForm(candidate) &&
        candidate.length >= 4 &&
        candidate.length <= 80 &&
        !_isLabelOrNoise(candidate) &&
        !_isSectionBoundaryLabel(candidate) &&
        !_streetAddressRegex.hasMatch(candidate) &&
        !payers.contains(candidate.toLowerCase())) {
      return candidate;
    }
  }

  // 4. Fallback: Ako su i sitne labele ("Primalac:", "Svrha uplate:") i pravna
  // forma bili oštećeni uz ivicu okvira, pronađi naziv primaoca neposredno iznad
  // njegovog poštanskog broja i mesta (5 cifara + grad), van bloka platioca.
  for (var i = 1; i < lines.length; i++) {
    if (payerIndices.contains(i)) continue;
    final postalCandidate = _cleanEntityName(
      _stripRightColumnTail(lines[i].split('   ').first),
    );
    if (!_fullSerbianPostalRegex.hasMatch(postalCandidate) ||
        payers.contains(postalCandidate.toLowerCase())) {
      continue;
    }
    for (var back = 1; back <= 2 && i - back >= 0; back++) {
      if (payerIndices.contains(i - back)) continue;
      final candidate = _cleanEntityName(
        _stripRightColumnTail(lines[i - back].split('   ').first),
      );
      if (candidate.length >= 3 &&
          candidate.length <= 80 &&
          !_isLabelOrNoise(candidate) &&
          !_isSectionBoundaryLabel(candidate) &&
          !_purposePhraseRegex.hasMatch(candidate) &&
          !_streetAddressRegex.hasMatch(candidate) &&
          !_postalCityRegex.hasMatch(candidate) &&
          !_brokenPostalTailRegex.hasMatch(candidate) &&
          !payers.contains(candidate.toLowerCase()) &&
          !RegExp(r'\d{6,}').hasMatch(candidate)) {
        return candidate;
      }
    }
  }

  return null;
}

/// Izvlači svrhu uplate ako je prisutna, uz zaštitu da nikada ne pređe u polje
/// primaoca ili platioca.
String? _extractPurpose(List<String> lines, {String? recipientName}) {
  final payerInfo = _extractPayerInfo(lines);
  final payers = payerInfo.names;
  final recipientLower = recipientName != null
      ? _cleanEntityName(recipientName).toLowerCase()
      : '';

  bool isInvalidPurposeCandidate(String candidate) {
    final clean = _cleanEntityName(candidate);
    if (clean.length < 3) return true;
    final lower = clean.toLowerCase();
    if (_isLabelOrNoise(clean) || _isSectionBoundaryLabel(clean)) return true;
    if (payers.contains(lower)) return true;
    if (recipientLower.isNotEmpty && lower == recipientLower) return true;
    if (_postalCityRegex.hasMatch(clean) ||
        _brokenPostalTailRegex.hasMatch(clean)) {
      return true;
    }
    // Ako kandidat sadrži pravnu formu (DOO, AD, JKP, JP), a ne počinje rečima
    // tipičnim za svrhu (npr. "Uplata...", "Račun..."), to je naziv primaoca, ne svrha.
    if (_hasLegalEntityForm(clean) && !_purposePhraseRegex.hasMatch(clean)) {
      return true;
    }
    return false;
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final lower = line.toLowerCase();
    if (_purposeLabelRegex.hasMatch(lower)) {
      final leftCell = _stripRightColumnTail(line.split('   ').first);
      final inline = _cleanEntityName(
        leftCell.replaceFirst(
          RegExp(
            r'^.*?(?:(?:[sc]|lj)[vuao]?r[hknažz]a\s+(?:up[l1iunp]at[esao]|p[l1iunp]a[ćčc]a(?:nja|na|a)?)|\bsvrha)\s*[:\-.;]*\s*',
            caseSensitive: false,
          ),
          '',
        ),
      );
      if (inline.toLowerCase() != _cleanEntityName(leftCell).toLowerCase() &&
          !isInvalidPurposeCandidate(inline)) {
        return _normalizeCommonPurpose(inline);
      }
      for (var offset = 1; offset <= 4 && i + offset < lines.length; offset++) {
        final rawNext = _stripRightColumnTail(
          lines[i + offset].split('   ').first,
        );
        final next = _cleanEntityName(rawNext);
        if (next.isEmpty) continue;
        // Čim naiđemo na labelu Primaoca ili Platioca, prekidamo pretragu
        // kako svrha nikada ne bi preuzela vrednost iz sledećeg boksa uplatnice.
        if (_isRecipientLabelLine(next) || _payerLabelRegex.hasMatch(next)) {
          break;
        }
        if (!isInvalidPurposeCandidate(next)) {
          return _normalizeCommonPurpose(next);
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
    'uplatioca',
    'platilac',
    'platioca',
    'svrha uplate',
    'svrha plaćanja',
    'svrha placanja',
    'svrha',
    'uplate',
    'plaćanja',
    'placanja',
    'primalac',
    'primaoca',
    'remala',
    'rimala',
    'rimalac',
    'remalac',
    'račun primaoca',
    'racun primaoca',
    'račun',
    'racun',
    'tekući',
    'tekuci',
    'iznos',
    'šifra plaćanja',
    'sifra placanja',
    'šifra plaćaa',
    'sifra placaa',
    'šifra',
    'sifra',
    'valuta',
    'model',
    'modela',
    'broj',
    'odobrenje',
    'poziv na',
    'poziv na broj',
    'poziv na broj (odobrenje)',
    'nalog za uplatu',
    'izveštaj o uplati',
    'izvestaj o uplati',
    'pečat i potpis',
    'pecat i potpis',
    'mesto i datum',
    'rsd',
    'din',
    'dinara',
  };
  if (forbiddenExact.contains(lower) ||
      RegExp(
        r'^(?:[sc][vuao]r[hkna]a\s+(?:up[l1iunp]at[esao]|p[l1iunp]a[ćčc]a(?:nja|na|a)?)|svrha|p?r[iein]ma[lpi]a[cčidžou]|p?r[iein]mala|u?p?[l1i]?at[inml1p][l1i]a[cčdžo]?)\s*[:\-.;]?$',
        caseSensitive: false,
      ).hasMatch(lower)) {
    return true;
  }
  if (_containsAny(lower, const [
    'šif. pla.',
    'sif. pla.',
    'šif. kom.',
    'sif. kom.',
    'f. kom.',
    'šifra plaćanja',
    'sifra placanja',
    'šifra plaćaa',
    'sifra placaa',
    'tekući račun',
    'tekuci racun',
    'račun primaoca',
    'racun primaoca',
    'broj modela',
    'poziv na broj',
    'pečat i potpis',
    'pecat i potpis',
    'mesto i datum',
    'izveštaj o uplati',
    'izvestaj o uplati',
  ])) {
    return true;
  }
  if (lower.startsWith('račun primaoca') ||
      lower.startsWith('racun primaoca') ||
      lower.startsWith('poziv na') ||
      lower.startsWith('šifra plać') ||
      lower.startsWith('sifra plac') ||
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
  final normHaystack = ' ${_normalizeWords(haystack)} ';
  for (final n in needles) {
    final normNeedle = _normalizeWords(n);
    if (normNeedle.isEmpty) continue;
    final isAbbreviation = n.trimRight().endsWith('.');
    final target = isAbbreviation ? ' $normNeedle' : ' $normNeedle ';
    if (normHaystack.contains(target)) return true;
  }
  return false;
}

String _normalizeWords(String text) {
  return text
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .toLowerCase()
      .trim();
}

String _cleanEntityName(String text) {
  var cleaned = text
      .replaceAll(RegExp(r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$', unicode: true), '')
      .replaceAll(RegExp(r'^(?:[l|¦!]\s+)+|(?:\s+[l|¦!])+$'), '')
      .trim();
  // Ukloni lažni razmak unutar početnog akronima (npr. "E PS AD" -> "EPS AD", "J KP" -> "JKP")
  cleaned = cleaned.replaceFirstMapped(
    RegExp(r'^([A-ZČĆŽŠĐ])\s+([A-ZČĆŽŠĐ]{2})\b'),
    (m) => '${m.group(1)}${m.group(2)}',
  );
  return cleaned;
}

class _ScoredCandidate<T> {
  const _ScoredCandidate(this.value, this.score);
  final T value;
  final int score;
}
