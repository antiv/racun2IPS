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
String generateIpsString(InvoiceData data, {String type = 'PR'}) {
  final formattedAmount = 'RSD${data.amount.toStringAsFixed(2).replaceAll('.', ',')}';
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
