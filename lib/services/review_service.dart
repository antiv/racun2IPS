import 'package:shared_preferences/shared_preferences.dart';

/// Broji uspešno skenirane račune i pamti da li je ponuda za ocenjivanje
/// aplikacije već prikazana. Pita se tačno jednom, pa se flag nikad ne briše.
class ReviewService {
  static const _countKey = 'scanned_invoice_count';
  static const _promptedKey = 'review_prompt_shown';

  /// Posle koliko uspešno skeniranih računa nudimo ocenjivanje.
  static const promptAfter = 3;

  /// Beleži jedno uspešno skeniranje računa i vraća true ako je trenutak da
  /// se ponudi ocenjivanje (dostignut prag, a ponuda još nije prikazana).
  Future<bool> registerScan() async {
    final prefs = await SharedPreferences.getInstance();
    // Kad je ponuda već bila prikazana, brojač više nikoga ne zanima.
    if (prefs.getBool(_promptedKey) ?? false) return false;
    final count = (prefs.getInt(_countKey) ?? 0) + 1;
    await prefs.setInt(_countKey, count);
    return count >= promptAfter;
  }

  /// Trajno gasi ponudu — poziva se čim se sheet prikaže, bez obzira na to
  /// šta korisnik izabere.
  Future<void> markPrompted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_promptedKey, true);
  }
}
