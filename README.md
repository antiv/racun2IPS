# Invoice2IPS (Flutter)

[![CI](https://github.com/antiv/racun2IPS/actions/workflows/ci.yml/badge.svg)](https://github.com/antiv/racun2IPS/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.47.5-02569B?logo=flutter)](https://flutter.dev)

A modern mobile app for fast bill payment in Serbia: scan or import any invoice (paper photo, PDF, or text), extract payment details, and generate a standardized **NBS IPS QR code** ready to scan with any Serbian mobile banking app ("IPS skeniraj").

Available for iOS and Android. Website and store links: [https://antonijevic.rs/invoice2ips/](https://antonijevic.rs/invoice2ips/)

---

## 🚀 Key Features

### 1. Cascading Extraction Pipeline (Speed, Privacy & Accuracy)
The app uses a 3-tier analysis pipeline designed to process invoices offline and in milliseconds whenever possible, keeping cloud API usage as an edge-case fallback:

1. **Tier 1 — Fast On-Device QR Detection (`google_mlkit_barcode_scanning`):**
   - If an imported bill (photo or PDF) already contains an NBS IPS QR code, the app detects and decodes it locally in under 50ms, without running OCR or cloud APIs. Includes EXIF orientation normalization, 1600px resolution scaling, and region crops.
2. **Tier 2 — On-Device OCR (`google_mlkit_text_recognition`) + Deterministic Parser:**
   - When no QR code is present, an on-device OCR model recognizes text on the payment slip.
   - Handles Serbian Cyrillic by transliterating to Latin script, reconstructs payment slip column layouts, and identifies the recipient, account, amount, and reference number.
   - All extracted accounts and reference numbers are verified using mathematical **Modulo 97 (ISO 7064)** checksum validation. If validation passes, the slip is generated instantly and 100% offline with zero hallucinations.
3. **Tier 3 — Multimodal Gemini AI Fallback:**
   - Only when the algorithmic parser cannot construct a strictly valid payment slip (e.g., poor lighting, crumpled receipts, non-standard invoices, or handwriting), the document is sent to Google's Gemini multimodal model for structured extraction.

### 2. Versatile Input Methods
- **Camera**: Quick capture with auto-focus and flash support.
- **Gallery**: Pick photos or screenshots from the device gallery.
- **PDF Documents**: Import PDF bills (multi-page documents are rendered in high resolution for scanning).
- **Clipboard**: Paste raw payment instruction text (from SMS, Viber, WhatsApp, or emails).
- **System Share Intent**: Open or share images, PDFs, and text directly from other apps (Mail, Files, messaging apps) via `ACTION_SEND` and `ACTION_VIEW` on Android and iOS Share Extension.

### 3. Saved Codes & Recurring Bills
- **Templates vs. My Codes**: Keep recurring bills (electricity, utilities, internet) as templates, or save your own account IPS QR codes to receive payments.
- **Quick QR Sheet**: Tap a saved code to display a full-screen IPS QR code with on-the-fly amount editing (ideal for monthly utility bills with variable amounts).
- **Monthly Tracking**: Check off bills paid in the current month (automatically resets each month).
- **Pinning & Search**: Pin frequent bills to the top; search by name, recipient, account, or reference number.
- **Backup & Restore**: Export and import saved codes in JSON format.

---

## 🛠️ Development & Setup

### Prerequisites
- [FVM](https://fvm.app) (Flutter Version Management). The project uses Flutter `3.47.5` (defined in `.fvmrc`).
- Android SDK (API 34+) / Xcode (iOS 15.5+).
- Run all Flutter commands through `fvm flutter ...`.

### Environment Setup

1. **Install Flutter SDK via FVM:**
   ```sh
   fvm install
   fvm flutter pub get
   ```

2. **Configure Gemini API Key:**
   Copy the example environment file:
   ```sh
   cp .env.example .env
   ```
   Add your `GEMINI_API_KEY` to `.env`. The key is passed at compile time via `--dart-define-from-file`:
   ```sh
   fvm flutter run --dart-define-from-file=.env
   ```

3. **Android Release Signing (Optional):**
   `android/key.properties` (git-ignored) points to `release-key.jks`. Without it, Gradle automatically falls back to the debug signing configuration.

---

## 🧪 Testing & Linting

The repository includes unit tests covering NBS IPS standard formatting, ISO 7064 Modulo 97 check digit calculation, Cyrillic transliteration, deterministic slip parsing, and persistent storage:

```sh
fvm flutter test
fvm flutter analyze
```

---

## 📦 Build & Release

```sh
./deploy.sh              # Android App Bundle (.aab) for Google Play
./deploy.sh apk          # Android APK
./deploy.sh --upload     # Build AAB and upload to Google Play (Internal track)
./deploy_ios.sh          # iOS build and upload to TestFlight (App Store Connect)
```

Deployment scripts automatically load configurations and pass compilation arguments from `.env`.

---

## 🏛️ Project Architecture

- `lib/utils/ips.dart` — NBS IPS specification: 3-13-2 account normalization, ISO 7064 Modulo 97 validation, IPS QR string parsing and generation.
- `lib/utils/invoice_text_parser.dart` — Deterministic payment slip parser with Cyrillic transliteration and column reconstruction.
- `lib/services/qr_scanner_service.dart` — Multi-pass on-device QR scanner with EXIF normalization and payment slip region crops.
- `lib/services/local_ocr_service.dart` — On-device OCR block extraction and column layout analysis.
- `lib/services/gemini_service.dart` — Multimodal LLM fallback client for unstructured invoices.
- `lib/services/saved_codes_service.dart` — Persistent local storage (`SharedPreferences`) for saved templates and codes.
- `lib/widgets/quick_qr_sheet.dart` — Modal for full-screen QR display and quick amount adjustments.
- `android/` & `ios/` — Native platform channels for system Share Intents and high-resolution PDF page rendering.

---

## 🤝 Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) before submitting a Pull Request, and ensure that both `fvm flutter test` and `fvm flutter analyze` pass cleanly.

For security-related issues, please refer to [SECURITY.md](SECURITY.md).

---

## 📄 License

This project is open-source software licensed under the [MIT License](LICENSE).
