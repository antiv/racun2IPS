import '../constants/ips.dart';
import '../models/invoice_data.dart';

/// Uklanja pipe karaktere (delimiter) — nisu dozvoljeni u sadržaju IPS tagova.
String sanitizePipe(String val) => val.replaceAll('|', '');

/// Parsira račun sa crticama (npr. "115-12345-88") u ravan string od 18 cifara.
/// Ako nema crtica, uklanja sve što nije cifra.
String parseAccountNumber(String val) {
  if (val.isEmpty) return '';
  final parts = val.split('-');
  if (parts.length == 3) {
    final prefix = parts[0].replaceAll(RegExp(r'[^0-9]'), '');
    final middle = parts[1].replaceAll(RegExp(r'[^0-9]'), '');
    final suffix = parts[2].replaceAll(RegExp(r'[^0-9]'), '');
    // Standardni srpski račun = 18 cifara (PPP-NNNNNNNNNNNNN-KK).
    // Dopuni sredinu do tačno 18 ukupno, ako LLM koristi nestandardne podele.
    final middleTargetLen = 18 - prefix.length - suffix.length;
    final paddedMiddle = middle.padLeft(middleTargetLen, '0');
    return '$prefix$paddedMiddle$suffix';
  }
  return val.replaceAll(RegExp(r'[^0-9]'), '');
}

/// Normalizuje broj računa na tačno 18 cifara (PPP + 13 cifara sredine + KK).
String normalizeAccountNumber(String val) {
  final parsed = parseAccountNumber(val);
  if (parsed.length != 18 && parsed.length >= 5) {
    final bankPrefix = parsed.substring(0, 3);
    final checkDigits = parsed.substring(parsed.length - 2);
    final middle = parsed.substring(3, parsed.length - 2);
    final normalizedMiddle = middle.length <= 13
        ? middle.padLeft(13, '0')
        : middle.substring(middle.length - 13);
    return '$bankPrefix$normalizedMiddle$checkDigits';
  }
  return parsed;
}

/// Parsira postojeći NBS IPS QR string (npr. "K:PR|V:01|C:1|R:...|N:...|I:RSD...")
/// u [InvoiceData]. Vraća `null` ako string nije validan NBS IPS kod
/// (npr. URL sa fiskalnog računa ili promotivni QR kod).
InvoiceData? parseIpsString(String raw) {
  final trimmed = raw.trim();
  if (!trimmed.contains('|') || !trimmed.contains(':')) return null;

  final tags = <String, String>{};
  for (final part in trimmed.split('|')) {
    final segment = part.trim();
    if (segment.isEmpty) continue;
    final colonIdx = segment.indexOf(':');
    if (colonIdx <= 0) continue;
    final key = segment.substring(0, colonIdx).trim().toUpperCase();
    final value = segment.substring(colonIdx + 1).trim();
    tags[key] = value;
  }

  final kind = tags['K']?.toUpperCase();
  if (kind != 'PR' && kind != 'EK') return null;

  final rawAccount = tags['R'] ?? '';
  final accountNumber = normalizeAccountNumber(rawAccount);
  if (accountNumber.isEmpty) return null;

  final rawRecipient = (tags['N'] ?? '')
      .replaceAll(RegExp(r'[\r\n]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (rawRecipient.isEmpty) return null;
  final recipientName = rawRecipient.length > IpsLimits.n
      ? rawRecipient.substring(0, IpsLimits.n)
      : rawRecipient;

  var amount = 0.0;
  final rawAmount = tags['I'];
  if (rawAmount != null && rawAmount.isNotEmpty) {
    final numericPart = rawAmount
        .replaceFirst(RegExp(r'^RSD\s*', caseSensitive: false), '')
        .replaceAll('.', '')
        .replaceAll(',', '.')
        .trim();
    if (numericPart.isNotEmpty) {
      final parsed = double.tryParse(numericPart);
      if (parsed != null && !parsed.isNaN && parsed >= 0) {
        amount = parsed;
      }
    }
  }

  var paymentCode =
      (tags['SF'] ?? '289').replaceAll(RegExp(r'[^0-9]'), '');
  if (paymentCode.isEmpty) {
    paymentCode = '289';
  } else if (paymentCode.startsWith('1') && paymentCode.length == 3) {
    paymentCode = '2${paymentCode.substring(1)}';
  }
  if (paymentCode.length > IpsLimits.sf) {
    paymentCode = paymentCode.substring(0, IpsLimits.sf);
  }

  final rawPurpose = (tags['S'] ?? '')
      .replaceAll(RegExp(r'[\r\n]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final purpose = rawPurpose.length > IpsLimits.s
      ? rawPurpose.substring(0, IpsLimits.s)
      : rawPurpose;

  var referenceNumber = (tags['RO'] ?? '').replaceAll(RegExp(r'\s+'), '').trim();
  if (referenceNumber.startsWith('97')) {
    referenceNumber = referenceNumber.replaceAll('-', '');
  }
  if (referenceNumber.length > IpsLimits.ro) {
    referenceNumber = referenceNumber.substring(0, IpsLimits.ro);
  }

  return InvoiceData(
    recipientName: recipientName,
    accountNumber: accountNumber,
    amount: amount,
    paymentCode: paymentCode,
    purpose: purpose,
    referenceNumber: referenceNumber,
  );
}

/// Validira srpski broj računa Modulo 97 algoritmom (18 cifara).
bool validateAccountNumber(String account) {
  if (account.length != 18) return false;
  final first16 = account.substring(0, 16);
  final control = account.substring(16, 18);
  final num = BigInt.tryParse('${first16}00');
  if (num == null) return false;
  final expectedControl = BigInt.from(98) - (num % BigInt.from(97));
  final expectedStr = expectedControl.toString().padLeft(2, '0');
  return control == expectedStr;
}

/// Validira poziv na broj. Ako počinje sa '97', mora proći Modulo 97 proveru.
bool validateReferenceNumber(String ref) {
  if (ref.isEmpty) return true; // Poziv na broj je opcion
  final cleanRef = ref.replaceAll(RegExp(r'[- ]'), '');
  if (cleanRef.length > IpsLimits.ro) return false;

  if (cleanRef.startsWith('97')) {
    if (cleanRef.length < 4) return false;
    final controlStr = cleanRef.substring(2, 4);
    final baseStr = cleanRef.substring(4).toUpperCase();

    final numBuf = StringBuffer();
    for (var i = 0; i < baseStr.length; i++) {
      final code = baseStr.codeUnitAt(i);
      if (code >= 48 && code <= 57) {
        numBuf.write(baseStr[i]); // 0-9
      } else if (code >= 65 && code <= 90) {
        numBuf.write(code - 55); // A-Z -> 10-35
      } else {
        return false;
      }
    }

    final num = BigInt.tryParse('${numBuf}00');
    if (num == null) return false;
    final expectedControl = BigInt.from(98) - (num % BigInt.from(97));
    return controlStr == expectedControl.toString().padLeft(2, '0');
  }

  return true;
}

/// Generiše NBS IPS QR string iz podataka o računu.
///
/// Format: K:[TYPE]|V:01|C:1|R:[Račun]|N:[Primalac]|I:RSD[Iznos]|SF:[Šifra]|S:[Svrha]|RO:[Poziv]
///
/// [type]: PR = Plaćanje Računa (standardni QR), EK = Elektronska Kupovina.
/// [allowOpenAmount]: kod ličnog IPS koda ("IPS pokaži") iznos je opcion —
/// kad je 0/negativan, izostavlja se cifra iznosa (I:RSD bez broja) da
/// platilac sam unese koliko šalje. Podrazumevano isključeno da postojeći
/// tok plaćanja tuđeg računa (gde je iznos > 0 uvek obavezan) ostane isti.
String generateIpsString(
  InvoiceData data, {
  String type = 'PR',
  bool allowOpenAmount = false,
}) {
  final formattedAmount = (allowOpenAmount && data.amount <= 0)
      ? 'RSD'
      : 'RSD${data.amount.toStringAsFixed(2).replaceAll('.', ',')}';
  var cleanAccount = data.accountNumber.replaceAll(RegExp(r'[^0-9]'), '');
  if (cleanAccount.length > IpsLimits.r) {
    cleanAccount = cleanAccount.substring(0, IpsLimits.r);
  }

  String clip(String v, int max) => v.length > max ? v.substring(0, max) : v;

  // Ukloni pipe iz svih tekstualnih polja (nije dozvoljen u sadržaju taga).
  final recipientName = clip(sanitizePipe(data.recipientName), IpsLimits.n);
  final purpose = clip(
    sanitizePipe(data.purpose.isEmpty ? 'Uplata po računu' : data.purpose),
    IpsLimits.s,
  );
  final paymentCode = clip(
    sanitizePipe(data.paymentCode.isEmpty ? '289' : data.paymentCode)
        .replaceAll(RegExp(r'[^0-9]'), ''),
    IpsLimits.sf,
  );

  final parts = [
    'K:$type',
    'V:01',
    'C:1',
    'R:$cleanAccount',
    'N:$recipientName',
    'I:$formattedAmount',
    'SF:$paymentCode',
    'S:$purpose',
  ];

  if (data.referenceNumber.isNotEmpty) {
    // Ukloni razmake i pipe karaktere
    var cleanRef = sanitizePipe(data.referenceNumber).replaceAll(RegExp(r'\s+'), '');
    // Ukloni "model" prefiks ako je slučajno uključen
    cleanRef = cleanRef.replaceFirst(RegExp(r'^(model|mod)', caseSensitive: false), '');
    // Zadrži samo alfanumerike i crtice
    cleanRef = cleanRef.replaceAll(RegExp(r'[^a-zA-Z0-9-]'), '');

    // Ako je model 97, crtice NISU dozvoljene
    if (cleanRef.startsWith('97')) {
      cleanRef = cleanRef.replaceAll('-', '');
    }

    cleanRef = clip(cleanRef, IpsLimits.ro);

    parts.add('RO:$cleanRef');
  }

  return parts.join('|');
}
