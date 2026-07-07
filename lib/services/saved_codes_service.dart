import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/invoice_data.dart';
import '../models/saved_code.dart';

/// Perzistencija sačuvanih IPS kodova preko shared_preferences,
/// kao jedan JSON-enkodiran niz.
class SavedCodesService {
  static const _key = 'saved_ips_codes';

  Future<List<SavedCode>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => SavedCode.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> add(SavedCode code) async {
    final codes = await loadAll();
    codes.add(code);
    await _writeAll(codes);
  }

  Future<void> update(String id, InvoiceData data) async {
    final codes = await loadAll();
    final index = codes.indexWhere((c) => c.id == id);
    if (index == -1) return;
    codes[index].data = data;
    await _writeAll(codes);
  }

  Future<void> delete(String id) async {
    final codes = await loadAll();
    codes.removeWhere((c) => c.id == id);
    await _writeAll(codes);
  }

  /// Izvoz svih sačuvanih kodova kao JSON string (za prenos na drugi uređaj).
  Future<String> exportJson() async {
    final codes = await loadAll();
    return jsonEncode(codes.map((c) => c.toJson()).toList());
  }

  /// Uvoz iz JSON stringa (izvezenog preko [exportJson]) — dodaje samo
  /// zapise čiji id već ne postoji, da ponovni uvoz istog fajla ne
  /// duplira postojeće kodove. Vraća broj novo dodatih zapisa.
  /// Baca [FormatException] ako sadržaj nije validan niz sačuvanih kodova.
  Future<int> importMerge(String raw) async {
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('Očekivan je niz sačuvanih kodova.');
    }
    final incoming =
        decoded.map((e) => SavedCode.fromJson(e as Map<String, dynamic>)).toList();
    final existing = await loadAll();
    final existingIds = existing.map((c) => c.id).toSet();
    final newOnes = incoming.where((c) => !existingIds.contains(c.id)).toList();
    if (newOnes.isNotEmpty) {
      existing.addAll(newOnes);
      await _writeAll(existing);
    }
    return newOnes.length;
  }

  Future<void> _writeAll(List<SavedCode> codes) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(codes.map((c) => c.toJson()).toList());
    await prefs.setString(_key, raw);
  }
}
