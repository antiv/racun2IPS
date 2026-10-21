# Doprinos projektu (Contributing)

Hvala vam na interesovanju za unapređenje projekta **Invoice2IPS**!

## Razvojno okruženje

1. **Flutter verzija**: Verzija Flutter SDK-a je definisana u `.fvmrc` (`3.47.5`). Preporučujemo korišćenje [FVM](https://fvm.app):
   ```sh
   fvm install
   fvm flutter pub get
   ```
2. **Podešavanje okruženja**:
   Kopirajte `.env.example` u `.env` i unesite svoj Gemini API ključ (potreban za AI ekstrakciju kada račun nema IPS QR kod i ne prolazi lokalni OCR):
   ```sh
   cp .env.example .env
   ```

## Pokretanje aplikacije i testova

- Pokretanje na uređaju / emulatoru:
  ```sh
  fvm flutter run --dart-define-from-file=.env
  ```
- Pokretanje svih testova:
  ```sh
  fvm flutter test
  ```
- Statička analiza koda:
  ```sh
  fvm flutter analyze
  ```
- Formatiranje koda:
  ```sh
  dart format .
  ```

## Pravila i konvencije

- Komentari u kodu i poruke commit-ova pišu se na srpskom jeziku (ili na engleskom za konvencionalne prefikse poput `feat:`, `fix:`, `chore:`).
- Pre otvaranja Pull Request-a obavezno proverite da `fvm flutter analyze` i `fvm flutter test` prolaze bez ijedne greške ili upozorenja.
- Nikada nemojte commit-ovati privatne fajlove (`.env`, `key.properties`, `release-key.jks`, `deploy.env`).
