import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../i18n/translations.dart';
import '../models/saved_code.dart';
import '../theme.dart';
import '../utils/format.dart';

/// Zajednički red sačuvanog koda: ikona po vrsti, naziv sa oznakama
/// (prikačeno/plaćeno), podnaslov i proizvoljan desni deo. Koristi se na
/// početnom ekranu (sekcija sačuvanih) i na ekranu sačuvanih kodova.
class SavedCodeTile extends StatelessWidget {
  const SavedCodeTile({
    super.key,
    required this.t,
    required this.code,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(14, 12, 12, 12),
  });

  final Translations t;
  final SavedCode code;
  // Ako nije zadat, koristi se podrazumevani (primalac • maskiran račun).
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsets padding;

  static String maskedAccount(SavedCode code) {
    final acc = code.data.accountNumber;
    if (acc.length < 4) return acc;
    return '•••• ${acc.substring(acc.length - 4)}';
  }

  static String amountLabel(SavedCode code, Translations t) {
    final amount = code.data.amount;
    if (amount <= 0) return t.openAmountLabel;
    return '${formatAmount(amount)} RSD';
  }

  static String displayTitle(SavedCode code) {
    if (code.title.isNotEmpty) return code.title;
    if (code.data.recipientName.isNotEmpty) return code.data.recipientName;
    return maskedAccount(code);
  }

  String get _defaultSubtitle {
    if (code.title.isNotEmpty) {
      return code.data.recipientName.isNotEmpty
          ? '${code.data.recipientName} • ${maskedAccount(code)}'
          : maskedAccount(code);
    }
    return code.data.purpose.isNotEmpty
        ? code.data.purpose
        : maskedAccount(code);
  }

  @override
  Widget build(BuildContext context) {
    final isOwn = code.kind == SavedCodeKind.ownAccount;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isOwn ? AppColors.emerald50 : AppColors.stone100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isOwn ? LucideIcons.user : LucideIcons.receipt,
              size: 18,
              color: isOwn ? AppColors.emerald600 : AppColors.stone600,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        displayTitle(code),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.stone900,
                        ),
                      ),
                    ),
                    if (code.isPinned) ...[
                      const SizedBox(width: 5),
                      const Icon(
                        LucideIcons.pin,
                        size: 13,
                        color: AppColors.emerald600,
                      ),
                    ],
                    if (code.isPaidThisMonth) ...[
                      const SizedBox(width: 6),
                      _Badge(label: t.paidBadge),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle ?? _defaultSubtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.stone500,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
      decoration: BoxDecoration(
        color: AppColors.emerald100,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: AppColors.emerald700,
        ),
      ),
    );
  }
}
