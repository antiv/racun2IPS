import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../i18n/translations.dart';
import '../theme.dart';

/// Meni iz headera: izbor jezika, O aplikaciji, izvoz/uvoz sačuvanih kodova
/// i ocenjivanje aplikacije.
/// Akcije se pozivaju tek nakon zatvaranja sheet-a, da se novi sheet/dijalog
/// ne otvara preko ovog.
Future<void> showAppMenuSheet(
  BuildContext context, {
  required Translations t,
  required Language language,
  required ValueChanged<Language> onLanguageChanged,
  required VoidCallback onInfo,
  required VoidCallback onExport,
  required VoidCallback onImport,
  required VoidCallback onRate,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    barrierColor: AppColors.stone900.withValues(alpha: 0.42),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetCtx) => _AppMenu(
      t: t,
      language: language,
      onLanguageChanged: onLanguageChanged,
      onAction: (action) {
        Navigator.of(sheetCtx).pop();
        action();
      },
      onInfo: onInfo,
      onExport: onExport,
      onImport: onImport,
      onRate: onRate,
    ),
  );
}

class _AppMenu extends StatefulWidget {
  const _AppMenu({
    required this.t,
    required this.language,
    required this.onLanguageChanged,
    required this.onAction,
    required this.onInfo,
    required this.onExport,
    required this.onImport,
    required this.onRate,
  });

  final Translations t;
  final Language language;
  final ValueChanged<Language> onLanguageChanged;
  final void Function(VoidCallback action) onAction;
  final VoidCallback onInfo;
  final VoidCallback onExport;
  final VoidCallback onImport;
  final VoidCallback onRate;

  @override
  State<_AppMenu> createState() => _AppMenuState();
}

class _AppMenuState extends State<_AppMenu> {
  late Language _lang = widget.language;

  static const _languageNames = {
    Language.sr: 'Srpski',
    Language.en: 'English',
  };

  @override
  Widget build(BuildContext context) {
    // Prevodi u samom meniju prate izbor odmah, bez ponovnog otvaranja.
    final t = translations[_lang]!;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 10, 16, 20 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.stone200,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                t.language.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: AppColors.stone500,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.stone100,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  for (final l in Language.values)
                    Expanded(
                      child: _SegmentButton(
                        label: _languageNames[l]!,
                        selected: _lang == l,
                        onTap: () {
                          setState(() => _lang = l);
                          widget.onLanguageChanged(l);
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Container(
              decoration: BoxDecoration(
                color: AppColors.stone50,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.stone100),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _MenuRow(
                    icon: LucideIcons.info,
                    label: t.infoTitle,
                    onTap: () => widget.onAction(widget.onInfo),
                  ),
                  const Divider(height: 1, thickness: 1, color: AppColors.stone100),
                  _MenuRow(
                    icon: LucideIcons.upload,
                    label: t.exportCodes,
                    onTap: () => widget.onAction(widget.onExport),
                  ),
                  const Divider(height: 1, thickness: 1, color: AppColors.stone100),
                  _MenuRow(
                    icon: LucideIcons.download,
                    label: t.importCodes,
                    onTap: () => widget.onAction(widget.onImport),
                  ),
                  const Divider(height: 1, thickness: 1, color: AppColors.stone100),
                  _MenuRow(
                    icon: LucideIcons.star,
                    label: t.reviewRate,
                    onTap: () => widget.onAction(widget.onRate),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snapshot) => Text(
                snapshot.hasData ? '${t.version} ${snapshot.data!.version}' : '',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppColors.stone500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Jedan segment u kontroli za izbor (jezik, filter).
class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.stone900 : AppColors.stone500,
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppColors.emerald600),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.stone900,
                  ),
                ),
              ),
              const Icon(LucideIcons.chevronRight, size: 18, color: AppColors.stone400),
            ],
          ),
        ),
      ),
    );
  }
}
