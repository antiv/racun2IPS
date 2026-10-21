import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../i18n/translations.dart';
import '../theme.dart';

/// Ekran obrade: animirani bot u prstenu, rotirajuće statusne poruke,
/// disclaimer, umanjena slika računa sa skener efektom preko nje.
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

  late final AnimationController _scan = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  )..repeat(reverse: true);

  Timer? _stepTimer;
  int _stepIndex = 0;

  @override
  void initState() {
    super.initState();
    _stepTimer = Timer.periodic(const Duration(milliseconds: 1700), (_) {
      if (!mounted) return;
      setState(() {
        _stepIndex = (_stepIndex + 1) % widget.t.processingSteps.length;
      });
    });
  }

  @override
  void dispose() {
    _spin.dispose();
    _bob.dispose();
    _sparkle.dispose();
    _scan.dispose();
    _stepTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final steps = widget.t.processingSteps;
    final step = steps[_stepIndex % steps.length];
    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
          SizedBox(
            width: 132,
            height: 132,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Blagi pulsirajući sjaj iza bota — utisak "razmišljanja".
                AnimatedBuilder(
                  animation: _sparkle,
                  builder: (context, child) {
                    final t = (math.sin(_sparkle.value * 2 * math.pi) + 1) / 2;
                    return Container(
                      width: 100 + 14 * t,
                      height: 100 + 14 * t,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.emerald400.withValues(alpha: 0.10 + 0.08 * t),
                      ),
                    );
                  },
                ),
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
          const SizedBox(height: 8),
          SizedBox(
            height: 20,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.35),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: Text(
                step,
                key: ValueKey(step),
                style: const TextStyle(fontSize: 14, color: AppColors.stone500),
              ),
            ),
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
                  child: Stack(
                    children: [
                      Opacity(
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
                      // Skener linija koja putuje preko slike, kao da se čita.
                      Positioned.fill(
                        child: AnimatedBuilder(
                          animation: _scan,
                          builder: (context, child) => CustomPaint(
                            painter: _ScanLinePainter(progress: _scan.value),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
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

/// Horizontalna glow linija koja putuje gore-dole preko slike, simulirajući
/// skeniranje dokumenta redom po redom.
class _ScanLinePainter extends CustomPainter {
  _ScanLinePainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * progress;

    final glowPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.emerald400.withValues(alpha: 0),
          AppColors.emerald400.withValues(alpha: 0.55),
          AppColors.emerald400.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromLTWH(0, y - 16, size.width, 32))
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, y - 16, size.width, 32), glowPaint);

    final linePaint = Paint()
      ..color = AppColors.emerald400.withValues(alpha: 0.9)
      ..strokeWidth = 2;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
  }

  @override
  bool shouldRepaint(covariant _ScanLinePainter oldDelegate) =>
      oldDelegate.progress != progress;
}
