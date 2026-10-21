import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

/// Otvara sistemski file picker i vraća sadržaj izabranog .json fajla kao
/// string, ili null ako je korisnik otkazao izbor.
Future<String?> pickJsonBackupContent() async {
  try {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.isEmpty) return null;

    final file = result.files.single;
    final bytes = await file.readAsBytes();
    return utf8.decode(bytes);
  } catch (e) {
    debugPrint('Greška pri uvozu backup JSON fajla: $e');
    return null;
  }
}

/// Otvara sistemski file picker za izbor .pdf računa i vraća njegove bajtove,
/// ili null ako je korisnik otkazao izbor.
Future<Uint8List?> pickPdfDocumentBytes() async {
  try {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result == null || result.files.isEmpty) return null;

    final file = result.files.single;
    return await file.readAsBytes();
  } catch (e) {
    debugPrint('Greška pri izboru PDF računa: $e');
    return null;
  }
}
