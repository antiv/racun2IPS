import 'invoice_data.dart';

/// Sačuvani lični IPS kod ("IPS pokaži") — wrapper oko InvoiceData sa
/// stabilnim id-jem i datumom čuvanja, za listu/pretragu.
class SavedCode {
  SavedCode({required this.id, required this.createdAt, required this.data});

  final String id;
  final DateTime createdAt;
  InvoiceData data;

  factory SavedCode.fromJson(Map<String, dynamic> json) => SavedCode(
        id: json['id'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        data: InvoiceData.fromJson(json['data'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'data': data.toJson(),
      };
}
