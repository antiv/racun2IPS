# Invoice2IPS (Flutter)

[![CI](https://github.com/antiv/racun2IPS/actions/workflows/ci.yml/badge.svg)](https://github.com/antiv/racun2IPS/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.47.5-02569B?logo=flutter)](https://flutter.dev)

Mobilna aplikacija za brzo plaćanje računa u Srbiji: skenira ili uvozi račun (sliku, PDF ili tekst), izvlači podatke za plaćanje i generiše standardni **NBS IPS QR kod** spreman za skeniranje bilo kojom domaćom mbanking aplikacijom ("IPS skeniraj").

Aplikacija je naslednik i Flutter port originalne Tauri aplikacije.

---

## 🚀 Mogućnosti

### 1. Kaskadna obrada računa (brzina i privatnost na prvom mestu)
Aplikacija koristi trostepenu analizu ulaznih računa kako bi trošila minimalno resursa i radila offline kad god je moguće:
1. **Tier 1 — Direktna detekcija NBS IPS QR koda (`google_mlkit_barcode_scanning`):**
   - Ako račun na slici ili PDF-u već sadrži NBS IPS QR kod (npr. EPS, Infostan, Telekom računi), aplikacija ga detektuje za nekoliko milisekundi, dešifruje i odmah prikazuje uplatnicu — bez OCR-a i bez poziva AI-ju.
2. **Tier 2 — Lokalni OCR (`google_mlkit_text_recognition`) + Deterministički parser:**
   - Ako nema QR koda, lokalni OCR model na uređaju čita tekst uplatnice. Rekonstruiše strukturu kolona i traži broj računa, iznos, poziv na broj i primaoca.
   - Podaci se validiraju strogim matematičkim pravilima (**Modulo 97** po NBS standardu). Ukoliko su svi ključni podaci pronađeni i validni, uplatnica se generiše momentalno i potpuno offline.
3. **Tier 3 — Gemini AI Fallback:**
   - Samo ukoliko lokalni OCR ne može pouzdano da izvuče podatke (loš snimak, rukom pisano, nestandardni format), slika ili tekst se šalju na Google Gemini multimodalni model.

### 2. Raznovrsni načini unosa
- **Kamera**: Brzo fotografisanje fizičkog računa sa automatskim fokusom i blicem.
- **Galerija slika**: Izbor fotografije ili screenshota iz galerije.
- **PDF dokumenti**: Uvoz PDF računa (višestranični PDF-ovi se automatski renderuju u visoku rezoluciju za analizu).
- **Nalepi tekst (Clipboard)**: Direktno lepljenje tekstualnih instrukcija za plaćanje (npr. iz SMS poruke, Viber-a ili email-a).
- **Sistemski "Share to" Intent**: Deljenje slika, PDF dokumenata ili teksta direktno iz bilo koje druge aplikacije (npr. Mail, Files, WhatsApp).

### 3. Pametno upravljanje sačuvanim računima
- **Šabloni računa vs. Moji kodovi**: Razdvajanje fiksnih šablona za mesečne režije od sopstvenih kodova za prijem uplata.
- **Brzi QR pregled**: Klik na račun otvara čist QR kod preko celog ekrana sa mogućnošću brze izmene iznosa na licu mesta (idealno za mesečne račune sa promenljivim iznosom).
- **Evidencija mesečnog plaćanja**: Oznaka da li je račun plaćen u tekućem mesecu (automatski se resetuje novog meseca).
- **Pinovanje i pretraga**: Važni računi na vrhu liste, brza pretraga po nazivu, primaocu, broju računa ili pozivu na broj.
- **Backup & Restore**: Izvoz i uvoz svih sačuvanih kodova u JSON formatu.

---

## 🛠️ Razvoj i podešavanje

### Zahtevi
- [FVM](https://fvm.app) (Flutter Version Management). Verzija Fluttera je definisana u `.fvmrc` (`3.47.5`).
- Android SDK (API 34+) / Xcode (iOS 15.5+).
- Sve komande pokretati kroz `fvm flutter ...`.

### Podešavanje okruženja

1. **Instalacija Flutter SDK-a preko FVM-a:**
   ```sh
   fvm install
   fvm flutter pub get
   ```

2. **Gemini API ključ:**
   Kopirajte primer konfiguracije:
   ```sh
   cp .env.example .env
   ```
   Unesite vaš `GEMINI_API_KEY` u fajl `.env`. Ključ se u aplikaciju prosleđuje u compile-time fazi:
   ```sh
   fvm flutter run --dart-define-from-file=.env
   ```

3. **Android potpisivanje (za release):**
   `android/key.properties` (nije u gitu) pokazuje na `release-key.jks`. Bez tog fajla Gradle koristi podrazumevani debug ključ.

---

## 🧪 Pokretanje testova

Projekat ima detaljne jedinične testove za NBS IPS validaciju (Modulo 97, formatiranje računa, poziva na broj), deterministički OCR parser i rad sa bazom sačuvanih kodova:

```sh
fvm flutter test
fvm flutter analyze
```

---

## 📦 Build i distribucija

```sh
./deploy.sh              # Android App Bundle (.aab) za Google Play
./deploy.sh apk          # Android APK
./deploy_ios.sh          # iOS build i upload na App Store Connect (TestFlight)
```

Skripte automatski prosleđuju konfiguraciju iz `.env`.

---

## 🏛️ Arhitektura projekta

- `lib/utils/ips.dart` — Standard NBS IPS formata: normalizacija računa (format 3-13-2), kontrolni broj Modulo 97 (ISO 7064), parsiranje i generisanje IPS QR nizova.
- `lib/utils/invoice_text_parser.dart` — Lokalni parser teksta uplatnice sa strogim proverama.
- `lib/services/qr_scanner_service.dart` — Detekcija i dekodiranje barkodova/QR kodova bez interneta.
- `lib/services/local_ocr_service.dart` — Rekonstrukcija i OCR čitanje blokova teksta na uplatnici.
- `lib/services/gemini_service.dart` — LLM multimodalni fallback za ekstrakciju podataka.
- `lib/services/saved_codes_service.dart` — Upravljanje bazom sačuvanih uplatnica (`SharedPreferences`).
- `lib/widgets/quick_qr_sheet.dart` — Brzi modal za prikaz QR koda i privremenu izmenu iznosa.
- `android/` i `ios/` — Native implementacije za Share Intent i PDF rendering u visoku rezoluciju.

---

## 🤝 Doprinos projektu (Contributing)

Doprinosi zajednice su dobrodošli! Pre slanja Pull Request-a, pročitajte [CONTRIBUTING.md](CONTRIBUTING.md) i proverite da `fvm flutter test` i `fvm flutter analyze` prolaze bez grešaka.

Za prijavu bezbednosnih ranjivosti, molimo pročitajte [SECURITY.md](SECURITY.md).

---

## 📄 Licenca

Ovaj projekat je licenciran pod [MIT licencom](LICENSE).
