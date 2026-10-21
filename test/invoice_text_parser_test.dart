import 'package:flutter_test/flutter_test.dart';
import 'package:invoice2ips/utils/invoice_text_parser.dart';

void main() {
  group('tryParseInvoiceText (Lokalni OCR parser)', () {
    test('izvlači podatke sa standardnog obrasca srpske uplatnice (Model 97)', () {
      const ocrText = '''
NALOG ZA UPLATU
Uplatilac
Petar Petrović, Bulevar Oslobođenja 12
Svrha uplate
Račun za oktobar 2026
Primalac
JKP INFOSTAN TEHNOLOGIJE BEOGRAD
Šifra plaćanja Valuta Iznos
189 RSD = 8.450,50
Račun primaoca
840-0000711171843-84
Model i poziv na broj (odobrenje)
97 78-123456789
''';

      final data = tryParseInvoiceText(ocrText);
      expect(data, isNotNull);
      expect(data!.recipientName, 'JKP INFOSTAN TEHNOLOGIJE BEOGRAD');
      expect(data.accountNumber, '840000071117184384');
      expect(data.amount, closeTo(8450.50, 0.001));
      expect(data.paymentCode, '289'); // 189 konvertovano u 289
      expect(data.purpose, 'Račun za oktobar 2026');
      expect(data.referenceNumber, '9778123456789');
    });

    test('izvlači podatke sa EPS računa sa tabelarnim prikazom', () {
      const ocrText = '''
AKCIONARSKO DRUŠTVO ELEKTROPRIVREDA SRBIJE BEOGRAD
EPS SNABDEVANJE
Obračunski period: 01.09.2026 - 30.09.2026
Utrošeno kWh: 412,00
Osnovica za PDV: 3.100,00
PDV (20%): 620,00
ZA UPLATU: 3.720,00 RSD
Tekući račun: 840-711171843-84
Model: 97
Poziv na broj: 78-123456789
''';

      final data = tryParseInvoiceText(ocrText);
      expect(data, isNotNull);
      expect(data!.accountNumber, '840000071117184384');
      expect(data.amount, closeTo(3720.00, 0.001));
      expect(data.referenceNumber, '9778123456789');
      expect(data.recipientName, contains('ELEKTROPRIVREDA SRBIJE'));
    });

    test('direktno prepoznaje ugrađen NBS IPS string u tekstu', () {
      const textWithIps = '''
Podaci za plaćanje:
K:PR|V:01|C:1|R:840000071117184384|N:Yettel d.o.o.|I:RSD2499,00|SF:289|S:Mesecni racun|RO:9778123456789
''';
      final data = tryParseInvoiceText(textWithIps);
      expect(data, isNotNull);
      expect(data!.recipientName, 'Yettel d.o.o.');
      expect(data.accountNumber, '840000071117184384');
      expect(data.amount, 2499.0);
      expect(data.referenceNumber, '9778123456789');
    });

    test('vraća null (aktivira AI fallback) ako račun ne prolazi Modulo-97', () {
      const invalidMod97Text = '''
Primalac: JKP Informatika
Za uplatu: 1.500,00 RSD
Račun primaoca: 840-0000711171843-99
''';
      expect(tryParseInvoiceText(invalidMod97Text), isNull);
    });

    test('vraća null (aktivira AI fallback) ako je Model 97 neispravan po Modulo-97', () {
      const invalidRefMod97Text = '''
Primalac: JKP Informatika
Za uplatu: 1.500,00 RSD
Račun primaoca: 840-0000711171843-84
Model: 97
Poziv na broj: 97 11-123456789
''';
      expect(tryParseInvoiceText(invalidRefMod97Text), isNull);
    });

    test('vraća null kada nedostaje iznos za uplatu', () {
      const missingAmountText = '''
Primalac: JKP Informatika
Račun primaoca: 840-0000711171843-84
''';
      expect(tryParseInvoiceText(missingAmountText), isNull);
    });

    test('uspešno izvlači ćirilični EPS račun sa "Уплатом од... попуста"', () {
      const cyrillicEps = '''
Уплатом од 2.894,64 динара остварујете један од следећих попуста: 5%, 6% или 7%. Детаље можете погледати на полеђини рачуна.
Уколико дуг не измирите до 28.10.2026. године, до дана уплате биће обрачуната камата у складу са законом.
У обрачуну задужења за обрачунски период (А) садржани су трошкови преноса и дистрибуције ел. енергије до купаца, који у овом месецу износе 1.379,14 динара.

Платилац:
АНТОНИЈЕВИЋ ИВАН
ДР ИВАНА РИБАРА 88/24, сп. 6;
БЕОГРАД - НОВИ БЕОГРАД
11073 БЕОГРАД 129

Сврха уплате:
Уплата по рачуну

Прималац:
ЕПС АД Београд
11000 Београд

Шиф. плаћ.   Валута   Износ
189          РСД
Шиф. ком.    Текући рачун примаоца
114          190-99870-10
Број модела  Позив на broj
97           17-02004377503-2609
''';

      final data = tryParseInvoiceText(cyrillicEps);
      expect(data, isNotNull);
      expect(data!.accountNumber, '190000000009987010');
      expect(data.amount, 2894.64);
      expect(data.recipientName, contains('EPS AD Beograd'));
      expect(data.paymentCode, '289');
      expect(data.referenceNumber, contains('17020043775032609'));
    });
  });
}
