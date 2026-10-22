import 'package:flutter_test/flutter_test.dart';
import 'package:invoice2ips/models/invoice_data.dart';
import 'package:invoice2ips/models/saved_code.dart';
import 'package:invoice2ips/services/saved_codes_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SavedCode model', () {
    test('migrira stari JSON bez kind/isPinned/lastPaidAt polja', () {
      final legacyJson = {
        'id': '12345',
        'createdAt': '2026-05-10T12:00:00.000',
        'data': {
          'recipientName': 'EPS AD Beograd',
          'accountNumber': '840000071117184384',
          'amount': 3500.0,
          'paymentCode': '289',
          'purpose': 'Struja',
          'referenceNumber': '9778123456789',
        },
      };

      final code = SavedCode.fromJson(legacyJson);
      expect(code.id, '12345');
      expect(code.kind, SavedCodeKind.billTemplate);
      expect(code.isPinned, isFalse);
      expect(code.lastPaidAt, isNull);
      expect(code.isPaidThisMonth, isFalse);
      expect(code.title, isEmpty);
      expect(code.data.amount, 3500.0);
    });

    test(
      'stari zapis bez iznosa i poziva na broj prepoznaje kao ownAccount',
      () {
        final legacyOwnJson = {
          'id': 'own-1',
          'createdAt': '2026-05-10T12:00:00.000',
          'data': {
            'recipientName': 'Petar Petrović',
            'accountNumber': '160000000123456789',
            'amount': 0.0,
            'paymentCode': '289',
            'purpose': '',
            'referenceNumber': '',
          },
        };

        final code = SavedCode.fromJson(legacyOwnJson);
        expect(code.kind, SavedCodeKind.ownAccount);
      },
    );

    test('isPaidThisMonth tačno proverava tekući mesec i godinu', () {
      final now = DateTime.now();
      final paidThisMonth = SavedCode(
        id: '1',
        createdAt: now.subtract(const Duration(days: 60)),
        lastPaidAt: DateTime(now.year, now.month, 1),
        data: InvoiceData(amount: 1000),
      );
      expect(paidThisMonth.isPaidThisMonth, isTrue);

      final paidLastMonth = SavedCode(
        id: '2',
        createdAt: now.subtract(const Duration(days: 60)),
        lastPaidAt: now.month == 1
            ? DateTime(now.year - 1, 12, 15)
            : DateTime(now.year, now.month - 1, 15),
        data: InvoiceData(amount: 1000),
      );
      expect(paidLastMonth.isPaidThisMonth, isFalse);
    });
  });

  group('SavedCodesService', () {
    test('dodavanje, pinovanje, toggle plaćanja i ažuriranje iznosa', () async {
      final service = SavedCodesService();
      final code = SavedCode(
        id: 'code-1',
        createdAt: DateTime.now(),
        title: 'Struja - Stan',
        kind: SavedCodeKind.billTemplate,
        data: InvoiceData(
          accountNumber: '840000071117184384',
          amount: 2500.0,
          referenceNumber: '9778123456789',
          recipientName: 'EPS Snabdevanje',
        ),
      );

      await service.add(code);
      var all = await service.loadAll();
      expect(all.length, 1);
      expect(all.first.isPinned, isFalse);

      // Pinuj
      await service.togglePin('code-1');
      all = await service.loadAll();
      expect(all.first.isPinned, isTrue);

      // Ažuriraj iznos
      await service.updateAmount('code-1', 3200.0);
      all = await service.loadAll();
      expect(all.first.data.amount, 3200.0);

      // Označi kao plaćeno
      expect(all.first.isPaidThisMonth, isFalse);
      await service.togglePaidThisMonth('code-1');
      all = await service.loadAll();
      expect(all.first.isPaidThisMonth, isTrue);

      // Ponovni toggle skida oznaku
      await service.togglePaidThisMonth('code-1');
      all = await service.loadAll();
      expect(all.first.isPaidThisMonth, isFalse);
    });

    test(
      'findDuplicate pronalazi šablon sa istim računom i pozivom na broj',
      () async {
        final service = SavedCodesService();
        await service.add(
          SavedCode(
            id: 'code-1',
            createdAt: DateTime.now(),
            title: 'Infostan',
            data: InvoiceData(
              accountNumber: '840-0000711171843-84',
              referenceNumber: '9778123456789',
              amount: 5000,
            ),
          ),
        );

        final dup = await service.findDuplicate(
          accountNumber: '840000071117184384',
          referenceNumber: '9778123456789',
        );
        expect(dup, isNotNull);
        expect(dup!.id, 'code-1');

        final notDup = await service.findDuplicate(
          accountNumber: '840000071117184384',
          referenceNumber: '9799999999999',
        );
        expect(notDup, isNull);
      },
    );
  });
}
