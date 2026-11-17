import 'package:flutter_test/flutter_test.dart';
import 'package:invoice2ips/utils/invoice_text_parser.dart';

void main() {
  group('tryParseInvoiceText (Lokalni OCR parser)', () {
    test(
      'izvlači podatke sa standardnog obrasca srpske uplatnice (Model 97)',
      () {
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
      },
    );

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

    test(
      'vraća null (aktivira AI fallback) ako račun ne prolazi Modulo-97',
      () {
        const invalidMod97Text = '''
Primalac: JKP Informatika
Za uplatu: 1.500,00 RSD
Račun primaoca: 840-0000711171843-99
''';
        expect(tryParseInvoiceText(invalidMod97Text), isNull);
      },
    );

    test(
      'vraća null (aktivira AI fallback) ako je Model 97 neispravan po Modulo-97',
      () {
        const invalidRefMod97Text = '''
Primalac: JKP Informatika
Za uplatu: 1.500,00 RSD
Račun primaoca: 840-0000711171843-84
Model: 97
Poziv na broj: 97 11-123456789
''';
        expect(tryParseInvoiceText(invalidRefMod97Text), isNull);
      },
    );

    test('prihvata 0 kada nedostaje iznos za uplatu', () {
      const missingAmountText = '''
Primalac: JKP Informatika
Račun primaoca: 840-0000711171843-84
''';
      final data = tryParseInvoiceText(missingAmountText);
      expect(data, isNotNull);
      expect(data!.amount, 0.0);
      expect(data.accountNumber, '840000071117184384');
      expect(data.recipientName, 'JKP Informatika');
    });

    test('uspešno procesira EPS uplatnicu sa praznim poljem za iznos', () {
      const epsEmptyAmountText = '''
Платилац:
АНТОНИЈЕВИЋ ИВАН
ДР ИВАНА РИБАРА 88/24
11073 БЕОГРАД

Сврха уплате:
Уплата по рачуну

Прималац:
ЕПС АД Београд
11000 Београд

Шиф. плаћ.  Валута   Износ
189         РСД

Шиф. ком.   Текући рачун примаоца
114         200-75409-96

Број модела     Позив на broj
97              14-02004377503-2610
''';
      final data = tryParseInvoiceText(epsEmptyAmountText);
      expect(data, isNotNull);
      expect(data!.amount, 0.0);
      expect(data.accountNumber, '200000000007540996');
      expect(data.recipientName, contains('EPS AD Beograd'));
      expect(data.referenceNumber, contains('14020043775032610'));
    });

    test(
      'uspešno procesira kompletan ćirilični račun sa tabelom, procentima i popustima',
      () {
        const cyrillicColumnText = '''
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
Шиф. плаћ.
189
Валута
РСД
Износ
Шиф. ком.
114
Текући рачун примаоца
200-75409-96
Број модела
97
Позив на број
14-02004377503-2610
''';
        const cyrillicHorizontalRows = '''
Одобрена снага:   17,25 kW
Утрошено у вишој тарифи (ВТ)   178 kWh   77,06 %
Утрошено у нижој тарифи (НТ)   53 kWh   22,94 %
10 Основица за ПДВ (4+5+6+7+9)   2.644,62
11 Износ ПДВ (20%)   528,92
14 ЗАДУЖЕЊЕ ЗА ОБРАЧУНСКИ ПЕРИОД (10+11+12+13)   3.173,54
А УКУПНО ЗАДУЖЕЊЕ ЗА ОБРАЧУНСКИ ПЕРИОД (14+15+16)   3.522,54
17 Задужење за претходни обрачунски период   2.894,64
18 Уплате и финансијске промене у току обрачунског периода   -2.894,64
19.10.2026   Уплата   2.894,64
УКУПНО   2.894,64
Б ПРЕПЛАТА ЗА ПРЕТХОДНИ ОБРАЧУНСКИ ПЕРИОД (17+18)   0,00
В ЗА УПЛАТУ ЗА ЕЛЕКТРИЧНУ ЕНЕРГИЈУ, НАКНАДЕ И ПОРЕЗЕ (А+Б)   3.522,54
5%   за уплату до 28.11.2026.г.   120,97
6%   за уплату до 20.11.2026.г. уз самоочитавање   145,17
7%   за уплату до 20.11.2026.г. уз електронски рачун   169,36
''';
        final data = tryParseInvoiceText(
          cyrillicColumnText,
          horizontalRowsText: cyrillicHorizontalRows,
        );
        expect(data, isNotNull);
        expect(data!.amount, closeTo(3522.54, 0.001));
        expect(data.accountNumber, '200000000007540996');
        expect(data.recipientName, 'EPS AD Beograd');
        expect(data.purpose, 'Uplata po računu');
        expect(data.paymentCode, '289');
        expect(data.referenceNumber, '9714020043775032610');
      },
    );

    test(
      'generički prepoznaje ključne reči i fraze bez obzira na proizvoljne simbole, okvire i linije tabela',
      () {
        const textWithArbitrarySymbols = '''
ПЛАТИЛАЦ: === ИВАН АНТОНИЈЕВИЋ ===
БЕОГРАД
*** Шиф. плаћ. 189 *** Валута РСД *** Износ ***
Текући рачун примаоца: 200-75409-96
Број модела 97 | Позив на број: 14-02004377503-2610
Сврха уплате: /// Уплата по рачуну ///
Прималац: [ЕПС АД Београд]
11000 Београд
Рачун за електричну енергију - ОКТОБАР 2026.
~~~ 8 __ЗА_УПЛАТУ___ЗА_ЕЛЕКТРИЧНУ_ЕНЕРГИЈУ ~~~
АКНАДЕ И ПОРЕЗЕ (А+6) 3522. 54 |
''';
        final data = tryParseInvoiceText(textWithArbitrarySymbols);
        expect(data, isNotNull);
        expect(data!.amount, closeTo(3522.54, 0.001));
        expect(data.accountNumber, '200000000007540996');
        expect(data.recipientName, 'EPS AD Beograd');
        expect(data.referenceNumber, '9714020043775032610');
      },
    );

    test(
      'uspešno prepoznaje iznos sa razmakom posle tačke/zareza iz OCR kamere (npr. "3522. 54")',
      () {
        const ocrCameraText = '''
ПЛАТИЛАЦ: АНТОНИЈЕВИЋ ИВАН
БЕОГРАД
Шиф. плаћ. 189   Валута РСД   Износ
Текући рачун примаоца: 200-75409-96
Број модела 97   Позив на број 14-02004377503-2610
Сврха уплате: Уплата по рачуну
Прималац: ЕПС АД Београд
11000 Београд
Рачун за електричну енергију - ОКТОБАР 2026.
8 __ЗА_УПЛАТУ ЗА ЕЛЕКТРИЧНУ ЕНЕРГИЈУ
АКНАДЕ И ПОРЕЗЕ (А+6 3522. 54 |
''';
        final data = tryParseInvoiceText(ocrCameraText);
        expect(data, isNotNull);
        expect(data!.amount, closeTo(3522.54, 0.001));
        expect(data.accountNumber, '200000000007540996');
        expect(data.recipientName, 'EPS AD Beograd');
        expect(data.referenceNumber, '9714020043775032610');
      },
    );

    test(
      'generički procesira ćirilične račune različitih izdavalaca i iOS Vision digrafe',
      () {
        const genericCyrillicText = '''
Платилац:
Марко Марковић
Његошева 15, Нови Сад
Сврха уплате:
Комуналне услуге за 10/2026
Прималац:
ЈКП ВОДОВОД И КАНАЛИЗАЦИЈА НОВИ САД
Масарикова 17, 21000 Нови Сад
Шифра плаћаьа: 189
Валута: РСД
Износ: = 1.845,20
Текући рачун примаоца: 840-0000711171843-84
Број модела: 97
Позив на број: 78-123456789
''';
        final data = tryParseInvoiceText(genericCyrillicText);
        expect(data, isNotNull);
        expect(data!.recipientName, 'JKP VODOVOD I KANALIZACIJA NOVI SAD');
        expect(data.purpose, 'Komunalne usluge za 10/2026');
        expect(data.accountNumber, '840000071117184384');
        expect(data.amount, closeTo(1845.20, 0.001));
        expect(data.paymentCode, '289');
        expect(data.referenceNumber, '9778123456789');
      },
    );

    test(
      'prihvata 0 kada iznos za uplatu nije pronađen čak i kada na računu postoje drugi brojevi',
      () {
        const billWithOtherNumbersNoTotal = '''
Платилац:
Петар Петровић
Сврха уплате:
Уплата по рачуну
Прималац:
ЈП СРБИЈАГАС НОВИ САД
Шиф. плаћ. 189   Валута РСД   Износ
Текући рачун примаоца: 840-0000711171843-84
Број модела: 97   Позив на број: 78-123456789
Утрошено: 178,50 m3 (77,06 %)
Основица за ПДВ: 2.644,62
ПДВ (10%): 264,46
Попуст 5% за уплату до 20.11.2026.г.: 120,97
''';
        final data = tryParseInvoiceText(billWithOtherNumbersNoTotal);
        expect(data, isNotNull);
        expect(data!.amount, 0.0);
        expect(data.recipientName, 'JP SRBIJAGAS NOVI SAD');
        expect(data.accountNumber, '840000071117184384');
        expect(data.referenceNumber, '9778123456789');
      },
    );

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

  group('tryParseInvoiceText — redosled teksta iz OCR-a po kolonama', () {
    // Latinični račun fotografisan kamerom: labele posle vrednosti, datum
    // "Rok za plaćanje" pre iznosa, platilac odmah ispod "Primalac:" i poziv
    // na broj dve linije ispod labele (između je "Broj modela").
    const ocrText = '''
Račun broj: 1234/26
Rok za plaćanje:
21.10.2026
Za uplatu
Cena
Količina
400,00
1,00
Zaduženje po računu:
400,00
Ukupno za uplatu:
NALOG ZA UPLATU
Platilac:
189
RSD
Petar Petrović
Tekući račun primaoca
160-0000000012345-95
Bulevar Oslobođenja 12
Poziv na broj
Broj modela
Svrha uplate:
089-024
Uplata po računu broj 1234/26
Platilac:
Primalac:
Petar Petrović
PRIMER ODRŽAVANJE DOO
Glavna 1
11070 Novi Beograd
''';

    test('datum se ne čita kao iznos, a labela posle vrednosti važi', () {
      final data = tryParseInvoiceText(ocrText);
      expect(data, isNotNull);
      expect(data!.amount, closeTo(400.0, 0.001));
    });

    test('poziv na broj se nalazi i nekoliko linija ispod labele', () {
      final data = tryParseInvoiceText(ocrText);
      expect(data!.referenceNumber, '00089-024');
      expect(data.purpose, 'Uplata po računu broj 1234/26');
    });

    test('platilac ispod labele "Primalac" se preskače', () {
      final data = tryParseInvoiceText(ocrText);
      expect(data!.recipientName, 'PRIMER ODRŽAVANJE DOO');
      expect(data.accountNumber, '160000000001234595');
    });

    test(
      'procenat i iznos iz rečenice ne potiskuju pravi iznos (ćirilica)',
      () {
        const text = '''
ЕПС АД Београд
2.894,64 дин
ЗА УПЛАТУ ЗА ЕЛЕКТРИЧНУ ЕНЕРГИЈУ (А+Б)
Рок за плаћање: 28.10.2026.
-24,62
Уплатом од 2.894,64 динара остварујете један од следећих попуста.
Текући рачун примаоца
190-99870-10
Позив на број
Број модела
97
92-1234567890
Платилац:
ПЕТАР ПЕТРОВИЋ
Прималац:
БУЛЕВАР ОСЛОБОЂЕЊА 12
ЕПС АД Београд
''';
        final data = tryParseInvoiceText(text);
        expect(data, isNotNull);
        expect(data!.amount, closeTo(2894.64, 0.001));
        expect(data.recipientName, 'EPS AD Beograd');
        expect(data.referenceNumber, '97921234567890');
      },
    );

    test('poziv na broj se ne uzima iz rečenice svrhe uplate', () {
      const text = '''
Ukupno za uplatu:
400,00
Platilac:
Petar Petrović
Tekući račun primaoca
160-0000000012345-95
Broj modela
Poziv na broj
Svrha uplate:
Uplata po računu broj 21850/26
089-024
Primalac:
PRIMER ODRŽAVANJE DOO
''';
      final data = tryParseInvoiceText(text);
      expect(data, isNotNull);
      expect(data!.referenceNumber, '00089-024');
      expect(data.purpose, 'Uplata po računu broj 21850/26');
    });

    test(
      'kamera OCR (ćirilica): oštećene labele, spojene kolone i zaštita da svrha ne preuzme primaoca',
      () {
        const cameraCyrillic = '''
l ПЛАТНЛАЦ: АНТОНИЈЕВИЋ ИВАН |
ДР ИВАНА РИБАРА 88/24
БЕОГРАД - НОВИ БЕОГРАД
11073 БЕОГРАД
Сврха уппате: Редовно одржаваье за 10/2026 Шиф. плаћ. 189 Валута РСД
Прнмалац ЈКП ИНФОСТАН ТЕХНОЛОГИЈЕ Текући рачун примаоца 840-0000711171843-84
Данијелова 33, 11000 Београд
Број модела 97 Позив на број 78-123456789
Укупно за уплату: 4.250,00 РСД
''';
        final data = tryParseInvoiceText(cameraCyrillic);
        expect(data, isNotNull);
        expect(data!.recipientName, 'JKP INFOSTAN TEHNOLOGIJE');
        expect(data.purpose, 'Redovno održavanje za 10/2026');
        expect(data.accountNumber, '840000071117184384');
        expect(data.referenceNumber, '9778123456789');
        expect(data.amount, closeTo(4250.0, 0.001));
      },
    );

    test(
      'kamera OCR: prazna svrha uplate ispod koje je odmah Primalac ne sme uzeti primaoca kao svrhu',
      () {
        const emptyPurposeSlip = '''
Платилац:
Петар Петровић
Булевар ослобођеьа 12
11000 Београд
Сврха уплате:
Прималац:
СТАМБЕНА ЗАЈЕДНИЦА КРАЉА МИЛАНА 14
11000 Београд
Шифра плаћаьа: 189
Износ: = 1.200,00
Текући рачун примаоца: 160-0000000012345-95
''';
        final data = tryParseInvoiceText(emptyPurposeSlip);
        expect(data, isNotNull);
        expect(data!.recipientName, 'STAMBENA ZAJEDNICA KRALJA MILANA 14');
        expect(data.purpose, 'Uplata po računu');
        expect(data.amount, closeTo(1200.0, 0.001));
      },
    );

    test(
      'kamera OCR: dvoredni naziv primaoca (naziv + DOO u sledećem redu)',
      () {
        const twoLineRecipient = '''
Платилац:
Марко Марковић
Сврха: Рачун за грејање
Прималац:
ТОПЛАНА ГРАДСКА
ЈКП КРАГУЈЕВАЦ
34000 Крагујевац
Текући рачун примаоца: 840-0000711171843-84
За уплату: 3.100,00 дин
''';
        final data = tryParseInvoiceText(twoLineRecipient);
        expect(data, isNotNull);
        expect(data!.recipientName, 'TOPLANA GRADSKA JKP KRAGUJEVAC');
        expect(data.purpose, 'Račun za grejanje');
      },
    );

    test(
      'kamera OCR: oštećena poštanska linija platioca ("НЕ ОРАД ад 129") i umetnuta desna kolona između "ремала" i "ЕПС АД Београд"',
      () {
        const cameraInterleaved = '''
Платилац:
АНТОНИЈЕВИЋ ИВАН
ДРУГЕ МОШТАНИЧКЕ БАТАЉОНЕ 12А
НЕ ОРАД ад 129
Сврха уплате:
Уплата по рачуну
ремала
Текући рачун:
200-0000000075409-96
Број модела:
Позив на број (одобрење):
17-02004377503-2609
МЕСТО И ДАТУМ ПРИЈЕМА
ЕПС АД Београд
11000 БЕОГРАД
В ЗА УПЛАТУ У ТЕКУЋЕМ ПЕРИОДУ (А+Б)   у.522. 54
''';
        final data = tryParseInvoiceText(cameraInterleaved);
        expect(data, isNotNull);
        expect(data!.recipientName, 'EPS AD Beograd');
        expect(data.purpose, 'Uplata po računu');
        expect(data.accountNumber, '200000000007540996');
        expect(data.referenceNumber, '9717020043775032609');
        expect(data.amount, closeTo(3522.54, 0.001));
      },
    );

    test(
      'kamera OCR: izbrisane sitne labele uz ivicu okvira, mešani verzal "Ад" i poštanski broj primaoca',
      () {
        const damagedLabelsMixedAd = '''
Платилац:
АНТОНИЈЕВИЋ ИВАН
ДР ИВАНА РИБАРА 88/24
НЕ ОРАД ад 129
.ска
Уплата по рачуну
Платилац:
АНТОНИЈЕВИЋ ИВАН
ЕПС Ад Београд
11000 Београд
Текући рачун примаоца: 200-75409-96
Број модела: 97
Позив на број: 14-02004377503-2610
В ЗА УПЛАТУ (А+Б) 3.522,54
''';
        final data1 = tryParseInvoiceText(damagedLabelsMixedAd);
        expect(data1, isNotNull);
        expect(data1!.recipientName, 'EPS Ad Beograd');
        expect(data1.accountNumber, '200000000007540996');
        expect(data1.referenceNumber, '9714020043775032610');
        expect(data1.amount, closeTo(3522.54, 0.001));

        const damagedLabelsPostalAnchor = '''
Платилац:
АНТОНИЈЕВИЋ ИВАН
ДР ИВАНА РИБАРА 88/24
11073 БЕОГРАД 129
.ска
Уплата по рачуну
ЕПС Београд
11000 Београд
Текући рачун примаоца: 200-75409-96
Број модела: 97
Позив на број: 14-02004377503-2610
В ЗА УПЛАТУ (А+Б) 3.522,54
''';
        final data2 = tryParseInvoiceText(damagedLabelsPostalAnchor);
        expect(data2, isNotNull);
        expect(data2!.recipientName, 'EPS Beograd');

        const missingFirstDashRef = '''
Платилац:
АНТОНИЈЕВИЋ ИВАН
Прималац:
ЕПС АД Београд
Текући рачун примаоца: 200-75409-96
Позив на broj: 1402004377503-2610
В ЗА УПЛАТУ (А+Б) 3.522,54
''';
        final data3 = tryParseInvoiceText(missingFirstDashRef);
        expect(data3, isNotNull);
        expect(data3!.referenceNumber, '9714020043775032610');
      },
    );
  });
}
