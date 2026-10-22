import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/invoice_data.dart';
import '../models/saved_code.dart';

/// Perzistencija sačuvanih IPS kodova i šablona računa preko shared_preferences,
/// kao jedan JSON-enkodiran niz sa podrškom za pinovanje, status plaćanja i brzu izmenu iznosa.
class SavedCodesService {
  static const _key = 'saved_ips_codes';

  Future<List<SavedCode>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => SavedCode.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> add(SavedCode code) async {
    final codes = await loadAll();
    codes.add(code);
    await _writeAll(codes);
  }

  Future<void> update(String id, InvoiceData data, {String? title}) async {
    final codes = await loadAll();
    final index = codes.indexWhere((c) => c.id == id);
    if (index == -1) return;
    codes[index].data = data;
    if (title != null) codes[index].title = title;
    codes[index].updatedAt = DateTime.now();
    await _writeAll(codes);
  }

  Future<void> updateAmount(String id, double newAmount) async {
    final codes = await loadAll();
    final index = codes.indexWhere((c) => c.id == id);
    if (index == -1) return;
    codes[index].data.amount = newAmount;
    codes[index].updatedAt = DateTime.now();
    await _writeAll(codes);
  }

  Future<void> togglePin(String id) async {
    final codes = await loadAll();
    final index = codes.indexWhere((c) => c.id == id);
    if (index == -1) return;
    codes[index].isPinned = !codes[index].isPinned;
    codes[index].updatedAt = DateTime.now();
    await _writeAll(codes);
  }

  Future<void> togglePaidThisMonth(String id) async {
    final codes = await loadAll();
    final index = codes.indexWhere((c) => c.id == id);
    if (index == -1) return;
    final code = codes[index];
    if (code.isPaidThisMonth) {
      code.lastPaidAt = null;
    } else {
      code.lastPaidAt = DateTime.now();
    }
    code.updatedAt = DateTime.now();
    await _writeAll(codes);
  }

  /// Traži postojeći sačuvani račun sa istim brojem računa i pozivom na broj
  /// (ili primaocem ako poziv na broj ne postoji).
  Future<SavedCode?> findDuplicate({
    required String accountNumber,
    required String referenceNumber,
    String? recipientName,
  }) async {
    if (accountNumber.isEmpty) return null;
    final codes = await loadAll();
    final cleanAcc = accountNumber.replaceAll(RegExp(r'[^0-9]'), '');

    for (final code in codes) {
      final codeAcc = code.data.accountNumber.replaceAll(RegExp(r'[^0-9]'), '');
      if (codeAcc != cleanAcc) continue;

      if (referenceNumber.isNotEmpty &&
          code.data.referenceNumber.isNotEmpty &&
          code.data.referenceNumber == referenceNumber) {
        return code;
      }

      if (referenceNumber.isEmpty &&
          recipientName != null &&
          recipientName.isNotEmpty &&
          code.data.recipientName.toLowerCase() ==
              recipientName.toLowerCase()) {
        return code;
      }
    }
    return null;
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
    final incoming = decoded
        .map((e) => SavedCode.fromJson(e as Map<String, dynamic>))
        .toList();
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
