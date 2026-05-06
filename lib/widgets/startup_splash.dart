import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

class StartupSplash extends StatefulWidget {
  const StartupSplash({
    super.key,
    required this.child,
    this.holdDuration = const Duration(milliseconds: 1500),
    this.fadeDuration = const Duration(milliseconds: 500),
  });

  final Widget child;
  final Duration holdDuration;
  final Duration fadeDuration;

  @override
  State<StartupSplash> createState() => _StartupSplashState();
}

class _StartupSplashState extends State<StartupSplash> {
  bool _visible = true;
  bool _fading = false;
  Timer? _holdTimer;
  Timer? _fadeTimer;

  @override
  void initState() {
    super.initState();
    _startExitAnimation();
  }

  void _startExitAnimation() {
    _holdTimer = Timer(widget.holdDuration, () {
      if (!mounted) return;

      setState(() => _fading = true);
      _fadeTimer = Timer(widget.fadeDuration, () {
        if (!mounted) return;

        setState(() => _visible = false);
      });
    });
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _fadeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_visible)
          AnimatedOpacity(
            opacity: _fading ? 0 : 1,
            duration: widget.fadeDuration,
            curve: Curves.easeOutCubic,
            child: const _SplashContent(),
          ),
      ],
    );
  }
}

class _SplashContent extends StatelessWidget {
  const _SplashContent();

  static const _background = Color(0xFFFFFBF5);
  static const _textColor = Color(0xFF263445);

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _SproutEnglishLogo(size: 118),
              const SizedBox(height: 20),
              Text(
                'Sprout English',
                textAlign: TextAlign.center,
                style:
                    Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: _textColor,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                      decoration: TextDecoration.none,
                    ) ??
                    const TextStyle(
                      color: _textColor,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                      decoration: TextDecoration.none,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SproutEnglishLogo extends StatelessWidget {
  const _SproutEnglishLogo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _SproutEnglishLogoPainter()),
    );
  }
}

class _SproutEnglishLogoPainter extends CustomPainter {
  static const _peach = Color(0xFFFF9276);
  static const _slate = Color(0xFF263445);
  static const _sprout = Color(0xFF72DDBE);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 118;
    final iconRect = Offset.zero & size;
    final radius = Radius.circular(24 * scale);

    canvas.drawRRect(
      RRect.fromRectAndRadius(iconRect, radius),
      Paint()..color = _peach,
    );

    final bubblePath = _bubblePath(size);
    canvas.drawPath(
      bubblePath,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      bubblePath,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * scale
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    final textPainter = TextPainter(
      text: TextSpan(
        text: 'Aa',
        style: TextStyle(
          color: _slate,
          fontSize: 44 * scale,
          fontWeight: FontWeight.w900,
          letterSpacing: -1 * scale,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset((size.width - textPainter.width) / 2, 34 * scale),
    );

    _paintSprout(canvas, size, scale);
  }

  Path _bubblePath(Size size) {
    final w = size.width;
    final h = size.height;

    return Path()
      ..moveTo(26 / 118 * w, 95 / 118 * h)
      ..cubicTo(
        22 / 118 * w,
        95 / 118 * h,
        20 / 118 * w,
        92 / 118 * h,
        22 / 118 * w,
        87 / 118 * h,
      )
      ..lineTo(25 / 118 * w, 77 / 118 * h)
      ..cubicTo(
        17 / 118 * w,
        70 / 118 * h,
        13 / 118 * w,
        61 / 118 * h,
        13 / 118 * w,
        51 / 118 * h,
      )
      ..cubicTo(
        13 / 118 * w,
        27 / 118 * h,
        34 / 118 * w,
        12 / 118 * h,
        59 / 118 * w,
        12 / 118 * h,
      )
      ..cubicTo(
        84 / 118 * w,
        12 / 118 * h,
        105 / 118 * w,
        27 / 118 * h,
        105 / 118 * w,
        51 / 118 * h,
      )
      ..cubicTo(
        105 / 118 * w,
        75 / 118 * h,
        84 / 118 * w,
        90 / 118 * h,
        59 / 118 * w,
        90 / 118 * h,
      )
      ..cubicTo(
        51 / 118 * w,
        90 / 118 * h,
        45 / 118 * w,
        89 / 118 * h,
        39 / 118 * w,
        86 / 118 * h,
      )
      ..cubicTo(
        35 / 118 * w,
        88 / 118 * h,
        31 / 118 * w,
        92 / 118 * h,
        26 / 118 * w,
        95 / 118 * h,
      )
      ..close();
  }

  void _paintSprout(Canvas canvas, Size size, double scale) {
    final stemPaint = Paint()
      ..color = _sprout
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6 * scale
      ..strokeCap = StrokeCap.round;

    final base = Offset(81 * scale, 102 * scale);
    final joint = Offset(84 * scale, 90 * scale);

    canvas.drawPath(
      Path()
        ..moveTo(base.dx, base.dy)
        ..cubicTo(
          86 * scale,
          96 * scale,
          87 * scale,
          92 * scale,
          joint.dx,
          joint.dy,
        ),
      stemPaint,
    );

    final leafPaint = Paint()..color = _sprout;
    final leftLeaf = _leafPath(
      center: Offset(75 * scale, 84 * scale),
      radiusX: 14 * scale,
      radiusY: 8 * scale,
      angle: math.pi * .18,
    );
    final rightLeaf = _leafPath(
      center: Offset(91 * scale, 81 * scale),
      radiusX: 17 * scale,
      radiusY: 9 * scale,
      angle: -math.pi * .45,
    );

    canvas.drawPath(leftLeaf, leafPaint);
    canvas.drawPath(rightLeaf, leafPaint);

    final veinPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * scale
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(78 * scale, 85 * scale)
        ..quadraticBezierTo(81 * scale, 86 * scale, 83 * scale, 90 * scale),
      veinPaint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(88 * scale, 87 * scale)
        ..quadraticBezierTo(92 * scale, 78 * scale, 99 * scale, 75 * scale),
      veinPaint,
    );
  }

  Path _leafPath({
    required Offset center,
    required double radiusX,
    required double radiusY,
    required double angle,
  }) {
    final path = Path()
      ..addOval(
        Rect.fromCenter(
          center: center,
          width: radiusX * 2,
          height: radiusY * 2,
        ),
      );

    final matrix = Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..rotateZ(angle)
      ..translateByDouble(-center.dx, -center.dy, 0, 1);

    return path.transform(matrix.storage);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
