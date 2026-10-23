# Contributing to Invoice2IPS

Thank you for your interest in improving **Invoice2IPS**! We welcome bug reports, feature suggestions, and code contributions.

---

## Development Workflow

1. **Flutter Version**: Flutter SDK version is pinned in `.fvmrc` (`3.47.5`). We recommend using [FVM](https://fvm.app):
   ```sh
   fvm install
   fvm flutter pub get
   ```

2. **Environment Configuration**:
   Copy `.env.example` to `.env` and set your `GEMINI_API_KEY` (used for the AI fallback extraction when local QR and OCR methods do not apply):
   ```sh
   cp .env.example .env
   ```

---

## Running the App & Tests

- **Run on a device or emulator:**
  ```sh
  fvm flutter run --dart-define-from-file=.env
  ```
- **Run the full test suite:**
  ```sh
  fvm flutter test
  ```
- **Static code analysis:**
  ```sh
  fvm flutter analyze
  ```
- **Code formatting:**
  ```sh
  dart format .
  ```

---

## Guidelines & Best Practices

- **Commits & PRs**: Use conventional commit messages (e.g. `feat:`, `fix:`, `refactor:`, `test:`, `chore:`).
- **Verification**: Ensure `fvm flutter analyze` and `fvm flutter test` pass without any warnings or failures before opening a pull request.
- **Privacy & Security**: Never commit private keys, `.env` files, or signing keystores (`android/key.properties`, `release-key.jks`, `ios/deploy.env`).
- **Standard Compliance**: Payment calculation and check digits must strictly follow the National Bank of Serbia (NBS) IPS QR specification and ISO 7064 Modulo 97 rules.

---

## Reporting Issues

- **Bug Reports & Feature Requests**: Please use the [GitHub Issue Tracker](https://github.com/antiv/racun2IPS/issues) and provide as much context as possible.
- **Security Vulnerabilities**: For responsible disclosure of security issues, please consult [SECURITY.md](SECURITY.md).
