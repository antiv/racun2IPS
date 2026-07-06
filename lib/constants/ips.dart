/// Gemini model za ekstrakciju podataka sa računa.
const geminiModel = 'gemini-3-flash-preview';

/// NBS IPS QR limiti po zvaničnoj specifikaciji (feb 2023).
class IpsLimits {
  IpsLimits._();

  /// Naziv primaoca: max 70 ans karaktera, max 3 reda.
  static const n = 70;

  /// Svrha plaćanja: max 35 ans karaktera, jedan red.
  static const s = 35;

  /// Poziv na broj: max 25 karaktera, jedan red.
  static const ro = 25;

  /// Šifra plaćanja: tačno 3 cifre.
  static const sf = 3;

  /// Broj računa: tačno 18 cifara.
  static const r = 18;
}
