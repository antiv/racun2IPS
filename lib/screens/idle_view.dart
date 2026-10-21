import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../i18n/translations.dart';
import '../theme.dart';

/// Početni ekran: hero dugme kamere, naslov, opis, dugmad kamera/galerija,
/// i kompaktne akcije za PDF račun i lepljenje teksta iz clipboard-a.
class IdleView extends StatelessWidget {
  const IdleView({
    super.key,
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
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(22, 26, 22, 22 + bottomInset),
      child: Column(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _HeroCameraButton(onTap: onOpenCamera, tooltip: t.openCamera),
                const SizedBox(height: 18),
                Text(
                  t.scanTitle,
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    color: AppColors.stone800,
                  ),
                ),
                const SizedBox(height: 18),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 270),
                  child: Text(
                    t.scanDesc,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14.5,
                      height: 1.6,
                      color: AppColors.stone500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _PrimaryButton(
            onTap: onOpenCamera,
            icon: Icons.photo_camera_outlined,
            label: t.openCamera,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(child: Divider(color: AppColors.stone100, height: 1)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  t.or.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.76,
                    color: AppColors.stone300,
                  ),
                ),
              ),
              const Expanded(child: Divider(color: AppColors.stone100, height: 1)),
            ],
          ),
          const SizedBox(height: 12),
          _SecondaryButton(
            onTap: onPickGallery,
            icon: Icons.file_upload_outlined,
            label: t.uploadGallery,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _CompactButton(
                  onTap: onPickPdf,
                  icon: Icons.picture_as_pdf_outlined,
                  label: t.pickPdf,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CompactButton(
                  onTap: onPasteClipboard,
                  icon: Icons.content_paste,
                  label: t.pasteClipboard,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () => launchUrl(Uri.parse('https://antonijevic.rs'),
                mode: LaunchMode.externalApplication),
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
        ],
      ),
    );
  }
}

class _HeroCameraButton extends StatelessWidget {
  const _HeroCameraButton({required this.onTap, required this.tooltip});

  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 116,
          height: 116,
          decoration: BoxDecoration(
            color: AppColors.emerald50,
            borderRadius: BorderRadius.circular(32),
            boxShadow: const [
              BoxShadow(
                color: Color(0x803D5E33),
                blurRadius: 30,
                offset: Offset(0, 10),
                spreadRadius: -12,
              ),
            ],
          ),
          child: const Icon(
            Icons.photo_camera_outlined,
            size: 50,
            color: AppColors.emerald600,
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.onTap, required this.icon, required this.label});

  final VoidCallback onTap;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton.icon(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.emerald600,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        icon: Icon(icon, size: 20),
        label: Text(label),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.onTap, required this.icon, required this.label});

  final VoidCallback onTap;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.stone600,
          backgroundColor: Colors.white,
          side: const BorderSide(color: AppColors.stone100, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        icon: Icon(icon, size: 20),
        label: Text(label),
      ),
    );
  }
}

class _CompactButton extends StatelessWidget {
  const _CompactButton({required this.onTap, required this.icon, required this.label});

  final VoidCallback onTap;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.stone600,
          backgroundColor: Colors.white,
          side: const BorderSide(color: AppColors.stone100, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        icon: Icon(icon, size: 18),
        label: FittedBox(fit: BoxFit.scaleDown, child: Text(label)),
      ),
    );
  }
}
