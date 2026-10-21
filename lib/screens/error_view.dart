import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../i18n/translations.dart';
import '../theme.dart';

/// Ekran greške: crvena ikona, naslov, poruka, "Pokušaj ponovo".
class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.t,
    required this.message,
    required this.onRetry,
  });

  final Translations t;
  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: const BoxDecoration(
                color: AppColors.red50,
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.circleAlert, size: 40, color: AppColors.red500),
            ),
            const SizedBox(height: 22),
            Text(
              t.errorTitle,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Text(
                message ?? t.processingError,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: AppColors.stone500),
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              height: 50,
              child: FilledButton(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.stone900,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 34),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: const TextStyle(
                  fontFamily: kFontFamily,fontWeight: FontWeight.w600),
                ),
                child: Text(t.tryAgain),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
