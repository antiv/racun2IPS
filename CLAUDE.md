# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Invoice2IPS — Flutter port of a Tauri app. Photographs a Serbian invoice, sends
it to Gemini for extraction of payment data, then generates an NBS IPS QR code
that Serbian banking apps can scan to pay the bill. Bundle ID
`rs.antonijevic.invoice2ips` on both Android and iOS (matches the original
Tauri app, so release builds legitimately upgrade that existing install).

Code comments and commit messages in this repo are written in Serbian; match
that convention when editing existing files.

## Commands

Flutter version is pinned via FVM (`.fvmrc` → 3.44.4) — always prefix commands
Flutter version is pinned via FVM (`.fvmrc` → 3.47.5) — always prefix commands
with `fvm`, not bare `flutter`.

```sh
fvm flutter run --dart-define-from-file=.env    # run (needs GEMINI_API_KEY, see below)
fvm flutter test                                # run all tests
fvm flutter test test/ips_test.dart             # run a single test file
fvm flutter test --plain-name "validan račun"   # run a single test by name
fvm flutter analyze                             # lint (flutter_lints via analysis_options.yaml)
```

One-time setup: `cp .env.example .env` and set `GEMINI_API_KEY` — it's compiled
in at build time via `--dart-define-from-file=.env`, required for both running
and building the app (extraction calls fail without it).

### Deploy

```sh
./deploy.sh              # Android AAB for Play Store, bumps patch+build version
./deploy.sh apk           # APK instead of AAB
./deploy.sh --no-bump     # skip version bump
./deploy_ios.sh           # iOS build + upload to App Store Connect
./deploy.sh                   # Android AAB za Play Store, bump patch+build verzije
./deploy.sh --upload          # Android AAB + automatski upload na Google Play (internal track)
./deploy.sh apk               # APK umesto AAB
./deploy.sh --no-bump         # bez podizanja verzije
./deploy.sh --upload --no-bump # upload postojećeg koda bez bump-a
./deploy_ios.sh               # iOS build + upload na App Store Connect
./deploy_ios.sh --no-upload
```

Both scripts read version from `pubspec.yaml` (`X.Y.Z+N`) and bump patch+build
by default. Android release signing needs `android/key.properties` (not in
git) pointing at `release-key.jks` in repo root; without it the release build
is signed with the debug key. iOS deploy needs `ios/deploy.env` (not in git,
is signed with the debug key. Android upload na Google Play koristi `tool/play_upload.py`
i zahteva `android/deploy.env` (šablon u `android/deploy.env.example`) sa
`PLAY_SERVICE_ACCOUNT_JSON` i `PLAY_TRACK`. iOS deploy needs `ios/deploy.env` (not in git,
template at `ios/deploy.env.example`) with App Store Connect API credentials.

Production: once the internal / TestFlight build is tested, `tool/promote.sh
--dry-run --notes en="…" --notes sr="…"` (then without `--dry-run`) moves the
`pubspec.yaml` version to the Play production track (`tool/play_promote.py`, no
re-upload) and submits the same build for App Store review
(`tool/asc_submit.py`). Notes are keyed by language and matched to each store
listing (`tool/release_notes.py`): Play has only `sr`, the App Store `en-US`
and `hr` (it has no Serbian; `hr` takes the `sr` note) — so both `en` and `sr`
are needed. The Play service account needs "Release apps to production".

## Architecture

### State machine, not routes

There's a single screen. `HomeScreen` (`lib/screens/home_screen.dart`) holds
all app state and switches between five body views based on `AppState`
(`lib/models/invoice_data.dart`): `idle → capturing → processing → result`,
with `error` reachable from `capturing`/`processing`. Each view
(`idle_view.dart`, `camera_view.dart`, `processing_view.dart`,
`result_view.dart`, `error_view.dart`) is a dumb widget driven entirely by
callbacks/props from `HomeScreen` — there's no independent state management
library (no Bloc/Riverpod/Provider).

### Image intake has two entry points that converge

1. In-app camera capture (`_capturePhoto`) or gallery pick (`_pickFromGallery`).
2. Android "Share" from another app (`ACTION_SEND`, image mime type), handled
   natively in `android/.../MainActivity.kt`. The Kotlin side stores the shared
   bytes in a static field and exposes them over MethodChannel
   `rs.antonijevic.invoice2ips/shared` (`getSharedImage`), consuming them once.
   The Dart side (`lib/services/shared_image.dart`) polls this channel every
   1.5s from `HomeScreen` (`_checkSharedImage`) — intentional, because Android
   intent delivery on resume is unreliable; don't replace this with a one-shot
   check.

Both paths funnel into `_processInvoice`, which calls
`lib/services/gemini_service.dart`.

### Extraction → IPS generation pipeline

- `gemini_service.dart` sends the photo + a fixed prompt to the Gemini REST
  API (model pinned in `lib/constants/ips.dart` as `geminiModel`), constrained
  by a JSON `responseSchema`, and maps the result onto `InvoiceData`. It
  normalizes payment codes (cash codes starting with `1` → non-cash `2`) and
  repairs malformed account numbers (Serbian accounts are always
  3+13+2 = 18 digits; the LLM sometimes gets the digit count wrong).
- `lib/utils/ips.dart` turns validated `InvoiceData` into the pipe-delimited
  NBS IPS QR string (`K:|V:|C:|R:|N:|I:|SF:|S:|RO:`) and implements the
  Modulo-97 checksum validation for both account numbers and "poziv na broj"
  (reference number, model 97). Field length limits from the official NBS IPS
  spec live in `lib/constants/ips.dart` (`IpsLimits`) — respect these when
  touching QR generation, since exceeding them produces a QR banks reject.
- Missing/invalid required fields are left as empty strings rather than
  thrown errors, so `ResultView` can show inline validation instead of a hard
  failure; only quota (429) and outright API/parse failures route to
  `AppState.error`.

### i18n

`lib/i18n/translations.dart` defines a `Translations` struct and a
`Map<Language, Translations>` (`Language.sr`/`Language.en`). No codegen or
`.arb` files — add new strings by adding a field to the struct and filling it
in for every `Language`. `HomeScreen` holds the current `Language` and passes
the resolved `Translations` down to child views as `t`.
