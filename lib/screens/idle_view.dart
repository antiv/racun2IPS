import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../i18n/translations.dart';
import '../models/saved_code.dart';
import '../theme.dart';
import '../widgets/saved_code_tile.dart';

/// Početni ekran: kartica za skeniranje (kamera, galerija, PDF, tekst iz
/// clipboard-a) i sekcija sa nekoliko sačuvanih kodova (prikačeni prvi).
class IdleView extends StatelessWidget {
  const IdleView({
    super.key,
    required this.t,
    required this.savedCodes,
    required this.onOpenCamera,
    required this.onPickGallery,
    required this.onPickPdf,
    required this.onPasteClipboard,
    required this.onOpenSavedList,
    required this.onOpenSavedCode,
  });

  // Broj sačuvanih kodova prikazanih na početnom ekranu.
  static const _previewCount = 3;

  final Translations t;
  final List<SavedCode> savedCodes;
  final VoidCallback onOpenCamera;
  final VoidCallback onPickGallery;
  final VoidCallback onPickPdf;
  final VoidCallback onPasteClipboard;
  final VoidCallback onOpenSavedList;
  final ValueChanged<SavedCode> onOpenSavedCode;

  List<SavedCode> get _preview {
    final list = [...savedCodes]
      ..sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        return b.updatedAt.compareTo(a.updatedAt);
      });
    return list.take(_previewCount).toList();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + bottomInset),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ScanCard(
                      t: t,
                      onOpenCamera: onOpenCamera,
                      onPickGallery: onPickGallery,
                      onPickPdf: onPickPdf,
                      onPasteClipboard: onPasteClipboard,
                    ),
                    const SizedBox(height: 22),
                    _SavedSection(
                      t: t,
                      total: savedCodes.length,
                      codes: _preview,
                      onOpenList: onOpenSavedList,
                      onOpenCode: onOpenSavedCode,
                    ),
                    const Spacer(),
                    const SizedBox(height: 20),
                    Center(
                      child: GestureDetector(
                        onTap: () => launchUrl(
                          Uri.parse('https://antonijevic.rs'),
                          mode: LaunchMode.externalApplication,
                        ),
                        child: Opacity(
                          opacity: 0.4,
                          child: ColorFiltered(
                            colorFilter: const ColorFilter.matrix(<double>[
                              0.2126, 0.7152, 0.0722, 0, 0,
                              0.2126, 0.7152, 0.0722, 0, 0,
                              0.2126, 0.7152, 0.0722, 0, 0,
                              0, 0, 0, 1, 0,
                            ]),
                            child: Image.asset('assets/images/ant-biocode.png', height: 15),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Bela kartica sa tankom ivicom — osnovni kontejner na početnom ekranu.
BoxDecoration _cardDecoration(double radius) => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: AppColors.stone200),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0A1C1917),
          blurRadius: 2,
          offset: Offset(0, 1),
        ),
      ],
    );

class _ScanCard extends StatelessWidget {
  const _ScanCard({
    required this.t,
    required this.onOpenCamera,
    required this.onPickGallery,
    required this.onPickPdf,
    required this.onPasteClipboard,
  });

  final Translations t;
  final VoidCallback onOpenCamera;
  final VoidCallback onPickGallery;
  final VoidCallback onPickPdf;
  final VoidCallback onPasteClipboard;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Tooltip(
                message: t.openCamera,
                child: GestureDetector(
                  onTap: onOpenCamera,
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.emerald50,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      LucideIcons.camera,
                      size: 28,
                      color: AppColors.emerald600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.scanTitle,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                        color: AppColors.stone900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t.scanDesc,
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.45,
                        color: AppColors.stone500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: onOpenCamera,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.emerald600,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                textStyle: const TextStyle(
                  fontFamily: kFontFamily,fontSize: 15.5, fontWeight: FontWeight.w600),
                elevation: 0,
              ),
              icon: const Icon(LucideIcons.camera, size: 20),
              label: Text(t.openCamera, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _SourceButton(
                  onTap: onPickGallery,
                  icon: LucideIcons.image,
                  label: t.uploadGallery,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SourceButton(
                  onTap: onPickPdf,
                  icon: LucideIcons.fileText,
                  label: t.pickPdf,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SourceButton(
                  onTap: onPasteClipboard,
                  icon: LucideIcons.clipboard,
                  label: t.pasteClipboard,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Dugme sa ikonom iznad teksta za alternativne izvore (galerija, PDF, tekst).
class _SourceButton extends StatelessWidget {
  const _SourceButton({required this.onTap, required this.icon, required this.label});

  final VoidCallback onTap;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.stone600,
          backgroundColor: AppColors.stone50,
          side: const BorderSide(color: AppColors.stone200),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.stone700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SavedSection extends StatelessWidget {
  const _SavedSection({
    required this.t,
    required this.total,
    required this.codes,
    required this.onOpenList,
    required this.onOpenCode,
  });

  final Translations t;
  final int total;
  final List<SavedCode> codes;
  final VoidCallback onOpenList;
  final ValueChanged<SavedCode> onOpenCode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        t.savedCodesTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          color: AppColors.stone900,
                        ),
                      ),
                    ),
                    if (total > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.stone100,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$total',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.stone600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              TextButton(
                onPressed: onOpenList,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.emerald700,
                  minimumSize: const Size(44, 44),
                  padding: const EdgeInsets.only(left: 10, right: 4),
                  textStyle: const TextStyle(
                  fontFamily: kFontFamily,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(t.showAll),
                    const Icon(LucideIcons.chevronRight, size: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        if (codes.isEmpty)
          _EmptySavedCard(t: t, onTap: onOpenList)
        else
          Container(
            decoration: _cardDecoration(20),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < codes.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, thickness: 1, color: AppColors.stone100),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => onOpenCode(codes[i]),
                      child: SavedCodeTile(
                        t: t,
                        code: codes[i],
                        subtitle: _subtitle(codes[i]),
                        trailing: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.emerald50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            LucideIcons.qrCode,
                            size: 20,
                            color: AppColors.emerald700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  String _subtitle(SavedCode code) {
    final recipient = code.title.isNotEmpty && code.data.recipientName.isNotEmpty
        ? code.data.recipientName
        : SavedCodeTile.maskedAccount(code);
    return '$recipient · ${SavedCodeTile.amountLabel(code, t)}';
  }
}

class _EmptySavedCard extends StatelessWidget {
  const _EmptySavedCard({required this.t, required this.onTap});

  final Translations t;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: _cardDecoration(20),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.stone100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(LucideIcons.qrCode, size: 22, color: AppColors.stone500),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.noSavedCodesTitle,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.stone800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t.noSavedCodesDesc,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: AppColors.stone500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(LucideIcons.circlePlus, size: 20, color: AppColors.emerald600),
            ],
          ),
        ),
      ),
    );
  }
}
