import 'package:flutter/material.dart';
import 'package:second_brain/core/theme/tokens.dart';

/// Geometric notebook mark. Drawn, not a generated picture.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Second Brain',
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
    final hair = Paint()..color = SbTokens.hairline;
    canvas.drawRRect(RRect.fromLTRBR(0, 0, s, s, Radius.circular(s * 0.18)), bg);

    final outer = RRect.fromLTRBR(s * 0.18, s * 0.18, s * 0.82, s * 0.82, Radius.circular(s * 0.12));
    canvas.drawRRect(outer, ink);
    final pad = s * 0.045;
    final inner = RRect.fromLTRBR(
      outer.left + pad,
      outer.top + pad,
      outer.right - pad,
      outer.bottom - pad,
      Radius.circular(s * 0.09),
    );
    canvas.drawRRect(inner, bg);

    final fold = s * 0.16;
    final foldPath = Path()
      ..moveTo(inner.right, inner.top)
      ..lineTo(inner.right - fold, inner.top)
      ..lineTo(inner.right, inner.top + fold)
      ..close();
    canvas.drawPath(foldPath, ink);

    final x0 = inner.left + inner.width * 0.18;
    var y = inner.top + inner.height * 0.42;
    final h = (s * 0.028).clamp(1.0, 3.0);
    for (final frac in [1.0, 0.78, 0.52]) {
      final w = inner.width * 0.58 * frac;
      canvas.drawRRect(
        RRect.fromLTRBR(x0, y, x0 + w, y + h, Radius.circular(h)),
        hair,
      );
      y += inner.height * 0.12;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
