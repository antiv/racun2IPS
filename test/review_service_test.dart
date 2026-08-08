import 'package:flutter_test/flutter_test.dart';
import 'package:invoice2ips/services/review_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ReviewService', () {
    test('prva dva skeniranja ne nude ocenjivanje, treće nudi', () async {
      final service = ReviewService();
      expect(await service.registerScan(), isFalse);
      expect(await service.registerScan(), isFalse);
      expect(await service.registerScan(), isTrue);
    });

    test('posle markPrompted se ocenjivanje više nikad ne nudi', () async {
      final service = ReviewService();
      await service.registerScan();
      await service.registerScan();
      await service.markPrompted();
      expect(await service.registerScan(), isFalse);
      expect(await service.registerScan(), isFalse);
    });

    test('brojač preživljava novu instancu servisa', () async {
      await ReviewService().registerScan();
      await ReviewService().registerScan();
      expect(await ReviewService().registerScan(), isTrue);
    });

    test('ponuda ostaje aktivna i posle praga dok se ne prikaže', () async {
      final service = ReviewService();
      await service.registerScan();
      await service.registerScan();
      expect(await service.registerScan(), isTrue);
      // Korisnik je npr. ubio aplikaciju pre nego što se sheet prikazao —
      // sledeće skeniranje ponovo nudi ocenjivanje.
      expect(await service.registerScan(), isTrue);
    });
  });
}
