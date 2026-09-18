import 'package:flutter/material.dart';
import 'package:second_brain/core/theme/tokens.dart';

/// Twin-lobe geometric mark. Drawn, not a generated picture.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'SecondBrain',
      image: true,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _BrandMarkPainter()),
      ),
    );
  }
}

class _BrandMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final bg = Paint()..color = SbTokens.darkBg;
    final ink = Paint()..color = SbTokens.darkTextHi;
    final echo = Paint()
      ..color = const Color(0xFF5A5854)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (s * 0.055).clamp(1.2, 3.5);
    canvas.drawRRect(RRect.fromLTRBR(0, 0, s, s, Radius.circular(s * 0.18)), bg);

    final m = s * 0.14;
    final span = s - 2 * m;
    final shift = Offset(span * 0.055, span * 0.04);

    void lobes(Offset o, Paint p) {
      final left = Rect.fromLTRB(m + span * 0.06, m + span * 0.16, m + span * 0.58, m + span * 0.78).shift(o);
      final right = Rect.fromLTRB(m + span * 0.38, m + span * 0.10, m + span * 0.94, m + span * 0.72).shift(o);
      final cere = Rect.fromLTRB(m + span * 0.18, m + span * 0.58, m + span * 0.52, m + span * 0.94).shift(o);
      canvas.drawOval(left, p);
      canvas.drawOval(right, p);
      canvas.drawOval(cere, p);
    }

    lobes(shift, echo);
    lobes(Offset.zero, ink);

    final cleft = Paint()
      ..color = SbTokens.darkBg
      ..strokeWidth = (s * 0.06).clamp(1.5, 4)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(m + span * 0.48, m + span * 0.20),
      Offset(m + span * 0.52, m + span * 0.68),
      cleft,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(
        m + span * 0.46,
        m + span * 0.78,
        m + span * 0.58,
        m + span * 0.97,
        Radius.circular(span * 0.04),
      ),
      ink,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
