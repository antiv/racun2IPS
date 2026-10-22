import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../i18n/translations.dart';
import '../theme.dart';

/// Soft-ask sheet: pita korisnika da li mu se aplikacija sviđa pre nego što
/// se pozove native prompt prodavnice. Tako se Play-ov ograničen broj prompt-a
/// ne troši na korisnike koji ionako ne bi ocenili.
/// Vraća true ako korisnik želi da oceni aplikaciju.
Future<bool?> showReviewSheet(BuildContext context, Translations t) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    barrierColor: AppColors.stone900.withValues(alpha: 0.42),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) {
      final bottomInset = MediaQuery.of(context).padding.bottom;
      return Padding(
        padding: EdgeInsets.fromLTRB(24, 10, 24, 20 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.stone200,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 22),
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.emerald50,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                LucideIcons.star,
                size: 36,
                color: AppColors.emerald600,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              t.reviewTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
                color: AppColors.stone900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              t.reviewMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.4,
                color: AppColors.stone600,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.stone900,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: kFontFamily,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Text(t.reviewRate),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.stone500,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: kFontFamily,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Text(t.reviewLater),
              ),
            ),
          ],
        ),
      );
    },
  );
}
