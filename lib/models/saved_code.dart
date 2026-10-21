import 'invoice_data.dart';

enum SavedCodeKind {
  /// Račun za plaćanje / šablon (npr. mesečni račun za struju, infostan, telefon).
  billTemplate,

  /// Sopstveni IPS kod ("IPS pokaži") koji se pokazuje drugima za uplatu.
  ownAccount,
}

/// Sačuvani IPS kod / šablon računa za plaćanje ili sopstveni kod.
class SavedCode {
  SavedCode({
    required this.id,
    required this.createdAt,
    required this.data,
    this.title = '',
    this.kind = SavedCodeKind.billTemplate,
    this.isPinned = false,
    this.lastPaidAt,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? createdAt;

  final String id;
  final DateTime createdAt;
  DateTime updatedAt;
  String title;
  SavedCodeKind kind;
  bool isPinned;
  DateTime? lastPaidAt;
  InvoiceData data;

  /// Da li je račun označen kao plaćen u tekućem mesecu.
  bool get isPaidThisMonth {
    final paid = lastPaidAt;
    if (paid == null) return false;
    final now = DateTime.now();
    return paid.year == now.year && paid.month == now.month;
  }

  factory SavedCode.fromJson(Map<String, dynamic> json) {
    final data = InvoiceData.fromJson(json['data'] as Map<String, dynamic>);
    final rawKind = json['kind'] as String?;
    final SavedCodeKind kind;
    if (rawKind != null) {
      kind = rawKind == 'ownAccount'
          ? SavedCodeKind.ownAccount
          : SavedCodeKind.billTemplate;
    } else {
      // Migracija starih zapisa: ako nema iznosa i poziva na broj, to je "IPS pokaži"
      kind = (data.amount <= 0 && data.referenceNumber.isEmpty)
          ? SavedCodeKind.ownAccount
          : SavedCodeKind.billTemplate;
    }

    final createdAt = DateTime.parse(json['createdAt'] as String);
    final rawUpdatedAt = json['updatedAt'] as String?;
    final rawLastPaid = json['lastPaidAt'] as String?;

    return SavedCode(
      id: json['id'] as String,
      createdAt: createdAt,
      updatedAt: rawUpdatedAt != null ? DateTime.parse(rawUpdatedAt) : createdAt,
      data: data,
      title: json['title'] as String? ?? '',
      kind: kind,
      isPinned: json['isPinned'] as bool? ?? false,
      lastPaidAt: rawLastPaid != null ? DateTime.parse(rawLastPaid) : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'title': title,
        'kind': kind.name,
        'isPinned': isPinned,
        'lastPaidAt': lastPaidAt?.toIso8601String(),
        'data': data.toJson(),
      };

  SavedCode copyWith({
    String? title,
    SavedCodeKind? kind,
    bool? isPinned,
    DateTime? lastPaidAt,
    DateTime? updatedAt,
    InvoiceData? data,
  }) {
    return SavedCode(
      id: id,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      title: title ?? this.title,
      kind: kind ?? this.kind,
      isPinned: isPinned ?? this.isPinned,
      lastPaidAt: lastPaidAt ?? this.lastPaidAt,
      data: data ?? this.data.copyWith(),
    );
  }
}
