import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../i18n/translations.dart';
import '../theme.dart';

/// Ekran obrade: animirani bot u prstenu koji se vrti, disclaimer,
/// umanjena slika računa (grayscale, blago rotirana).
class ProcessingView extends StatefulWidget {
  const ProcessingView({super.key, required this.t, this.image});

  final Translations t;
  final Uint8List? image;

  @override
  State<ProcessingView> createState() => _ProcessingViewState();
}

class _ProcessingViewState extends State<ProcessingView>
    with TickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat();

  late final AnimationController _bob = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  late final AnimationController _sparkle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _spin.dispose();
    _bob.dispose();
    _sparkle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 132,
            height: 132,
            child: Stack(
              alignment: Alignment.center,
              children: [
                RotationTransition(
                  turns: _spin,
                  child: CustomPaint(
                    size: const Size(132, 132),
                    painter: _RingPainter(),
                  ),
                ),
                AnimatedBuilder(
                  animation: _bob,
                  builder: (context, child) {
                    final phase = _bob.value * 2 * math.pi;
                    return Transform.translate(
                      offset: Offset(0, -4.5 + 4.5 * math.cos(phase)),
                      child: Transform.rotate(
                        angle: 0.06 * math.sin(phase * 2),
                        child: child,
                      ),
                    );
                  },
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(
                        Icons.smart_toy_outlined,
                        size: 50,
                        color: AppColors.emerald600,
                      ),
                      Positioned(
                        top: -8,
                        right: -8,
                        child: FadeTransition(
                          opacity: TweenSequence<double>([
                            TweenSequenceItem(tween: Tween(begin: 0, end: 1), weight: 1),
                            TweenSequenceItem(tween: Tween(begin: 1, end: 0), weight: 1),
                          ]).animate(_sparkle),
                          child: const Icon(
                            Icons.auto_awesome,
                            size: 17,
                            color: AppColors.amber400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          Text(
            widget.t.analyzing,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            widget.t.extracting,
            style: const TextStyle(fontSize: 14, color: AppColors.stone500),
          ),
          const SizedBox(height: 30),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.amber50,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.amber100),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, size: 19, color: AppColors.amber500),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    widget.t.disclaimer,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.6,
                      fontWeight: FontWeight.w500,
                      color: AppColors.amber700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (widget.image != null) ...[
            const SizedBox(height: 30),
            Transform.rotate(
              angle: 3 * math.pi / 180,
              child: Container(
                width: 128,
                height: 128,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white, width: 4),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Opacity(
                    opacity: 0.5,
                    child: ColorFiltered(
                      colorFilter: const ColorFilter.matrix(<double>[
                        0.2126, 0.7152, 0.0722, 0, 0,
                        0.2126, 0.7152, 0.0722, 0, 0,
                        0.2126, 0.7152, 0.0722, 0, 0,
                        0, 0, 0, 1, 0,
                      ]),
                      child: Image.memory(
                        widget.image!,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Prsten: svetli krug sa emerald lukom na vrhu (kao border-t spinner).
class _RingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = AppColors.emerald100;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = AppColors.emerald600;

    canvas.drawOval(rect, base);
    canvas.drawArc(rect, -math.pi / 2, math.pi / 2, false, arc);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
