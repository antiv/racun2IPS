import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Otvara sistemski file picker i vraća sadržaj izabranog .json fajla kao
/// string, ili null ako je korisnik otkazao izbor.
Future<String?> pickJsonBackupContent() async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['json'],
  );
  if (result == null || result.files.isEmpty) return null;

  final bytes = await result.files.single.readAsBytes();
  return utf8.decode(bytes);
}

/// Otvara sistemski file picker za izbor .pdf računa i vraća njegove bajtove,
/// ili null ako je korisnik otkazao izbor.
Future<Uint8List?> pickPdfDocumentBytes() async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['pdf'],
  );
  if (result == null || result.files.isEmpty) return null;

  return await result.files.single.readAsBytes();
}
