import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../i18n/translations.dart';
import '../theme.dart';

/// Info bottom sheet: ikona, naziv, verzija, "Powered by", zatvori.
Future<void> showInfoSheet(BuildContext context, Translations t) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    barrierColor: AppColors.stone900.withValues(alpha: 0.42),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) {
      final bottomInset = MediaQuery.of(context).padding.bottom;
      return SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 10, 24, 28 + bottomInset),
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
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.asset(
                  'assets/images/app-icon.png',
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 16),
              RichText(
                text: const TextSpan(
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                  children: [
                    TextSpan(
                      text: 'Invoice',
                      style: TextStyle(color: AppColors.emerald600),
                    ),
                    TextSpan(
                      text: '2IPS',
                      style: TextStyle(color: AppColors.stone900),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                t.subtitle.toUpperCase(),
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.76,
                  color: AppColors.stone400,
                ),
              ),
              const SizedBox(height: 24),
              _InfoRow(
                label: t.version.toUpperCase(),
                child: FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snapshot) => Text(
                    snapshot.hasData
                        ? '${snapshot.data!.version}+${snapshot.data!.buildNumber}'
                        : '…',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.stone600,
                    ),
                  ),
                ),
              ),
              _InfoRow(
                label: t.poweredBy.toUpperCase(),
                child: GestureDetector(
                  onTap: () => launchUrl(
                    Uri.parse('https://antonijevic.rs'),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: Image.asset(
                    'assets/images/ant-biocode.png',
                    height: 20,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.stone900,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: const TextStyle(
                  fontFamily: kFontFamily,fontWeight: FontWeight.w700),
                  ),
                  child: Text(t.close),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.stone100)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: AppColors.stone400,
            ),
          ),
          child,
        ],
      ),
    );
  }
}
