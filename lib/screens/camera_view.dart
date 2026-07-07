import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../i18n/translations.dart';
import '../models/invoice_data.dart';
import '../theme.dart';

String resShortText(CameraRes res) {
  switch (res) {
    case CameraRes.def:
      return 'A';
    case CameraRes.hd720:
      return 'HD';
    case CameraRes.fhd1080:
      return 'FHD';
    case CameraRes.max:
      return '4K';
  }
}

/// Ekran kamere: full-bleed preview, viewfinder sa animiranom scan linijom,
/// izbor rezolucije (gore levo), dole: nazad / okidač / lampa.
class CameraView extends StatefulWidget {
  const CameraView({
    super.key,
    required this.t,
    required this.controller,
    required this.cameraReady,
    required this.resolution,
    required this.torchOn,
    required this.hasTorch,
    required this.onBack,
    required this.onCapture,
    required this.onToggleTorch,
    required this.onSelectResolution,
  });

  final Translations t;
  final CameraController? controller;
  final bool cameraReady;
  final CameraRes resolution;
  final bool torchOn;
  final bool hasTorch;
  final VoidCallback onBack;
  final VoidCallback onCapture;
  final VoidCallback onToggleTorch;
  final ValueChanged<CameraRes> onSelectResolution;

  @override
  State<CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends State<CameraView>
    with SingleTickerProviderStateMixin {
  bool _showResPopup = false;

  late final AnimationController _scanLine = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _scanLine.dispose();
    super.dispose();
  }

  String _resLabel(CameraRes res) {
    switch (res) {
      case CameraRes.def:
        return widget.t.resDefault;
      case CameraRes.hd720:
        return widget.t.res720p;
      case CameraRes.fhd1080:
        return widget.t.res1080p;
      case CameraRes.max:
        return widget.t.resMax;
    }
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final controller = widget.controller;

    return Container(
      color: AppColors.cameraBg,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Video feed (cover)
          if (controller != null && controller.value.isInitialized)
            AnimatedOpacity(
              opacity: widget.cameraReady ? 1 : 0,
              duration: const Duration(milliseconds: 300),
              child: _CoverPreview(controller: controller),
            ),

          // Spinner dok se kamera učitava
          AnimatedOpacity(
            opacity: widget.cameraReady ? 0 : 1,
            duration: const Duration(milliseconds: 300),
            child: const Center(
              child: SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  strokeWidth: 4,
                  color: Colors.white,
                  backgroundColor: Colors.white24,
                ),
              ),
            ),
          ),

          // Viewfinder okvir sa scan linijom
          Positioned(
            top: 64,
            left: 28,
            right: 28,
            bottom: 150,
            child: IgnorePointer(
              child: CustomPaint(
                painter: _DashedBorderPainter(),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AnimatedBuilder(
                    animation: _scanLine,
                    builder: (context, _) => LayoutBuilder(
                      builder: (context, constraints) {
                        final travel = constraints.maxHeight;
                        final top = travel * (0.08 + 0.80 * _scanLine.value);
                        return Stack(
                          children: [
                            Positioned(
                              top: top,
                              left: 0,
                              right: 0,
                              child: Container(
                                height: 2,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(2),
                                  gradient: const LinearGradient(
                                    colors: [
                                      Colors.transparent,
                                      AppColors.emerald400,
                                      Colors.transparent,
                                    ],
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x6634D399),
                                      blurRadius: 8,
                                      spreadRadius: 4,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Klik van popup-a ga zatvara
          if (_showResPopup)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _showResPopup = false),
              ),
            ),

          // Chip za rezoluciju (gore levo)
          Positioned(
            top: topInset + 8,
            left: 10,
            child: IntrinsicWidth(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _GlassCircleButton(
                    size: 46,
                    onTap: () => setState(() => _showResPopup = !_showResPopup),
                    child: Text(
                      resShortText(widget.resolution),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (_showResPopup)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(minWidth: 140),
                      decoration: BoxDecoration(
                        color: AppColors.stone900.withValues(alpha: 0.96),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white24),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black54,
                            blurRadius: 20,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final res in CameraRes.values)
                            Material(
                              color: res == widget.resolution
                                  ? AppColors.emerald500.withValues(alpha: 0.8)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () {
                                  setState(() => _showResPopup = false);
                                  widget.onSelectResolution(res);
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                  child: Text(
                                    _resLabel(res),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: res == widget.resolution
                                          ? Colors.white
                                          : AppColors.stone300,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Donje kontrole
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomInset + 58,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _GlassCircleButton(
                  size: 50,
                  onTap: widget.onBack,
                  child: const Icon(
                    Icons.arrow_back,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 34),
                // Okidač
                GestureDetector(
                  onTap: widget.onCapture,
                  child: Container(
                    width: 78,
                    height: 78,
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.25),
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.stone900, width: 4),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 34),
                if (widget.hasTorch)
                  _GlassCircleButton(
                    size: 50,
                    color: widget.torchOn ? AppColors.emerald500 : null,
                    onTap: widget.onToggleTorch,
                    child: Icon(
                      widget.torchOn ? Icons.bolt : Icons.flash_off,
                      color: Colors.white,
                      size: 22,
                    ),
                  )
                else
                  const SizedBox(width: 50, height: 50),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Preview kamere razvučen preko celog ekrana (BoxFit.cover).
class _CoverPreview extends StatelessWidget {
  const _CoverPreview({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final previewSize = controller.value.previewSize;
    if (previewSize == null) return const SizedBox.shrink();
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          // previewSize je landscape; portret prikaz obrće dimenzije.
          width: previewSize.height,
          height: previewSize.width,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}

class _GlassCircleButton extends StatelessWidget {
  const _GlassCircleButton({
    required this.size,
    required this.onTap,
    required this.child,
    this.color,
  });

  final double size;
  final VoidCallback onTap;
  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color ?? Colors.white.withValues(alpha: 0.16),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}

/// Isprekidani zaobljeni okvir viewfinder-a (border-dashed iz originala).
class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(16),
    );
    final path = Path()..addRRect(rrect);

    const dashLength = 8.0;
    const gapLength = 6.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, distance + dashLength),
          paint,
        );
        distance += dashLength + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
