import 'package:flutter/material.dart';

import '../app_theme.dart';

/// The mark from the theme sheet: a white geometric "M" inside a solid red
/// circle (SVG: circle r=48 + path `M25 68 V32 L50 55 L75 32 V68`, stroke 10).
class MegaLogo extends StatelessWidget {
  const MegaLogo({
    super.key,
    this.size = 40,
    this.circle = AppTheme.megaRed,
    this.mark = Colors.white,
    this.glow = false,
  });

  final double size;
  final Color circle;
  final Color mark;

  /// Red drop-shadow, like `.logo-badge` in the sheet's header.
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final logo = CustomPaint(
      size: Size.square(size),
      painter: _MegaLogoPainter(circle, mark),
    );
    if (!glow) return logo;
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppTheme.megaRed.withValues(alpha: 0.45),
            blurRadius: size * 0.3,
            offset: Offset(0, size * 0.1),
          ),
        ],
      ),
      child: logo,
    );
  }
}

class _MegaLogoPainter extends CustomPainter {
  _MegaLogoPainter(this.circle, this.mark);

  final Color circle;
  final Color mark;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100; // viewBox is 100×100
    canvas.drawCircle(Offset(50 * s, 50 * s), 48 * s, Paint()..color = circle);
    final path = Path()
      ..moveTo(25 * s, 68 * s)
      ..lineTo(25 * s, 32 * s)
      ..lineTo(50 * s, 55 * s)
      ..lineTo(75 * s, 32 * s)
      ..lineTo(75 * s, 68 * s);
    canvas.drawPath(
      path,
      Paint()
        ..color = mark
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10 * s
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _MegaLogoPainter old) =>
      old.circle != circle || old.mark != mark;
}
