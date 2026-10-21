import 'package:flutter_test/flutter_test.dart';
import 'package:invoice2ips/models/invoice_data.dart';
import 'package:invoice2ips/utils/ips.dart';

void main() {
  group('parseAccountNumber', () {
    test('parsira račun sa crticama i dopunjava sredinu nulama', () {
      expect(parseAccountNumber('115-12345-88'), '115000000001234588');
      expect(parseAccountNumber('840-0000711171843-84'), '840000071117184384');
    });

    test('uklanja sve što nije cifra kad nema crtica', () {
      expect(parseAccountNumber('840 0000711171843 84'), '840000071117184384');
    });
  });

  group('validateAccountNumber', () {
    test('validan račun (mod 97)', () {
      // 840000071117184384: kontrolne cifre 84
      expect(validateAccountNumber('840000071117184384'), isTrue);
    });

    test('nevalidan račun', () {
      expect(validateAccountNumber('840000071117184385'), isFalse);
      expect(validateAccountNumber('12345'), isFalse);
      expect(validateAccountNumber(''), isFalse);
    });
  });

  group('validateReferenceNumber', () {
    test('prazan je validan (opcion)', () {
      expect(validateReferenceNumber(''), isTrue);
    });

    test('model 97 sa ispravnom kontrolom', () {
      // 97 + kontrola za "123456789": 98 - (12345678900 % 97) = 78
      expect(validateReferenceNumber('9778123456789'), isTrue);
      expect(validateReferenceNumber('9744123456789'), isFalse);
    });

    test('bez modela 97 sve prolazi do 25 karaktera', () {
      expect(validateReferenceNumber('00-123-456'), isTrue);
      expect(validateReferenceNumber('a' * 26), isFalse);
    });
  });

  group('generateIpsString', () {
    test('generiše ispravan NBS IPS string', () {
      final data = InvoiceData(
        recipientName: 'JKP Informatika',
        accountNumber: '840000071117184384',
        amount: 1234.5,
        paymentCode: '289',
        purpose: 'Uplata po računu',
        referenceNumber: '97-78123456789',
      );
      expect(
        generateIpsString(data),
        'K:PR|V:01|C:1|R:840000071117184384|N:JKP Informatika|'
        'I:RSD1234,50|SF:289|S:Uplata po računu|RO:9778123456789',
      );
    });

    test('uklanja pipe, podrazumeva svrhu i šifru', () {
      final data = InvoiceData(
        recipientName: 'Test|Primalac',
        accountNumber: '840000071117184384',
        amount: 100,
      );
      final ips = generateIpsString(data);
      expect(ips, contains('N:TestPrimalac'));
      expect(ips, contains('S:Uplata po računu'));
      expect(ips, contains('SF:289'));
      expect(ips, isNot(contains('RO:')));
    });

    test('bez allowOpenAmount, nulti iznos i dalje piše RSD0,00', () {
      final data = InvoiceData(
        recipientName: 'Moja Firma',
        accountNumber: '840000071117184384',
        amount: 0,
      );
      expect(generateIpsString(data), contains('I:RSD0,00'));
    });

    test('sa allowOpenAmount, nulti iznos daje otvoren iznos (bez cifara)', () {
      final data = InvoiceData(
        recipientName: 'Moja Firma',
        accountNumber: '840000071117184384',
        amount: 0,
      );
      final ips = generateIpsString(data, allowOpenAmount: true);
      expect(ips, contains('I:RSD|'));
    });
  });

  group('parseIpsString', () {
    test('parsira standardni NBS IPS QR string (round-trip)', () {
      final original = InvoiceData(
        recipientName: 'JKP Informatika Novi Sad',
        accountNumber: '840000071117184384',
        amount: 4567.89,
        paymentCode: '289',
        purpose: 'Račun za komunalne usluge',
        referenceNumber: '9778123456789',
      );
      final ips = generateIpsString(original);
      final parsed = parseIpsString(ips);

      expect(parsed, isNotNull);
      expect(parsed!.recipientName, original.recipientName);
      expect(parsed.accountNumber, original.accountNumber);
      expect(parsed.amount, closeTo(4567.89, 0.001));
      expect(parsed.paymentCode, '289');
      expect(parsed.purpose, original.purpose);
      expect(parsed.referenceNumber, '9778123456789');
    });

    test('parsira K:EK, konvertuje gotovinsku šifru 189 u 289 i otvoren iznos', () {
      const raw =
          'K:EK|V:01|C:1|R:840-0000711171843-84|N:EPS AD\nBEOGRAD|I:RSD|SF:189|S:Struja';
      final parsed = parseIpsString(raw);

      expect(parsed, isNotNull);
      expect(parsed!.accountNumber, '840000071117184384');
      expect(parsed.recipientName, 'EPS AD BEOGRAD');
      expect(parsed.amount, 0);
      expect(parsed.paymentCode, '289');
      expect(parsed.purpose, 'Struja');
      expect(parsed.referenceNumber, isEmpty);
    });

    test('ignoriše fiskalne QR URL-ove i ne-IPS tekst', () {
      expect(
        parseIpsString('https://suf.purs.gov.rs/v/?vl=A1B2C3D4'),
        isNull,
      );
      expect(parseIpsString('Običan tekst bez IPS tagova'), isNull);
      expect(parseIpsString('K:XX|V:01|R:840000071117184384|N:Test'), isNull);
    });
  });
}
