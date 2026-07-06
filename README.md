# Invoice2IPS (Flutter)

Flutter port Tauri aplikacije [invoice2ips](../invoice2ips): fotografiši račun,
AI (Gemini) izvuče podatke za plaćanje, aplikacija generiše NBS IPS QR kod za
skeniranje u bankarskoj aplikaciji.

- Bundle ID (Android i iOS): `rs.antonijevic.invoice2ips` — isti kao Tauri verzija
- Potpisivanje: isti Android keystore (`release-key.jks`) i isti iOS profil
  ("Invoice2IPS AppStore", team `8SDSB36733`), pa build-ovi legitimno nadograđuju
  postojeću aplikaciju na Play Store / App Store.

## Zahtevi

- [FVM](https://fvm.app) — verzija Fluttera je zakucana u `.fvmrc` (3.44.4).
  Sve komande pokretati kroz `fvm flutter ...`.

## Podešavanje (jednokratno)

1. **Gemini API ključ** — `cp .env.example .env` i upisati `GEMINI_API_KEY`.
   Ključ se u aplikaciju ubacuje pri build-u:

   ```sh
   fvm flutter run --dart-define-from-file=.env
   ```

2. **Android potpisivanje** — `android/key.properties` (nije u gitu) pokazuje na
   `release-key.jks` u root-u projekta (kopiran iz Tauri projekta). Bez tog fajla
   release build se potpisuje debug ključem.

3. **iOS deploy** — `ios/deploy.env` (nije u gitu) sadrži App Store Connect API
   kredencijale; šablon je `ios/deploy.env.example`.

## Deploy

```sh
./deploy.sh              # Android AAB za Play Store (+ bump verzije)
./deploy.sh apk          # APK
./deploy_ios.sh          # iOS build + upload na App Store Connect
```

Obe skripte same prosleđuju `--dart-define-from-file=.env`.

## Struktura

- `lib/utils/ips.dart` — NBS IPS format: parsiranje/validacija računa (mod 97),
  poziva na broj i generisanje IPS stringa
- `lib/services/gemini_service.dart` — ekstrakcija podataka sa slike računa
- `lib/screens/` — ekrani: idle / kamera / obrada / rezultat / greška
- `android/.../MainActivity.kt` — prijem slike podeljene iz druge aplikacije
  (ACTION_SEND), Flutter je preuzima preko MethodChannel-a

## Testovi

```sh
fvm flutter test
```
