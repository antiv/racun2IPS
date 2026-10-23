# Security Policy

User data security and privacy are fundamental principles in **Invoice2IPS**.

---

## Privacy by Design

- **Zero telemetry/tracking**: The app does not collect user data or transmit information to proprietary backend servers.
- **On-device extraction**:
  - Existing NBS IPS QR codes are scanned and decoded **100% locally on the device**.
  - Local OCR and payment slip parsing run **entirely on-device** using Google ML Kit.
- **Controlled cloud fallback**: Only when local deterministic methods fail (unclear images, non-standard layout, or handwriting) is the document sent to the Google Gemini API solely for structured data extraction.
- **Local storage**: All saved templates, payment history, and user codes are stored exclusively in the device's local sandboxed storage (`SharedPreferences`).

---

## Reporting a Vulnerability

If you discover a security vulnerability or privacy concern:

1. **Please do NOT disclose it publicly via GitHub Issues.**
2. Send a confidential report to `iantonijevic@gmail.com` with a detailed description of the issue and reproduction steps.
3. We will respond promptly, investigate, and publish a fix before public disclosure.
