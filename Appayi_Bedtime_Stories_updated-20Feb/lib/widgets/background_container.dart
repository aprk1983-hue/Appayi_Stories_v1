import 'dart:math';
import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';

/// Centralized App background inspired by appayistories.com:
/// - Deep blue/purple gradient
/// - Colorful twinkling sparkles/stars
/// - Soft outlined clouds
/// - Subtle music notes + hearts
///
/// Usage (per screen):
///   return AppBackground(child: Scaffold(...));
///
/// Usage (global):
///   MaterialApp(
///     builder: (context, child) => AppBackground(child: child ?? const SizedBox()),
///     ...
///   );
///
/// NOTE: If you wrap globally, any Scaffold with an opaque background will cover it.
class AppBackground extends StatefulWidget {
  final Widget child;

  /// If false, paints a static background (zero animation work).
  final bool animated;

  /// Dark overlay to improve contrast with foreground UI.
  final double dimOpacity;

  /// Force dark style regardless of theme.
  final bool? forceDarkStyle;

  const AppBackground({
    super.key,
    required this.child,
    this.animated = true,
    this.dimOpacity = 0.06,
    this.forceDarkStyle,
  });

  @override
  State<AppBackground> createState() => _AppBackgroundState();
}

class _AppBackgroundState extends State<AppBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<_Sparkle> _sparkles;
  late final List<_Cloud> _clouds;
  late final List<_Glyph> _glyphs;

  @override
  void initState() {
    super.initState();

    _generateParticles();

    // Faster, rhythmic animation (twinkle + gentle cloud drift)
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );

    if (widget.animated) {
      _ctrl.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant AppBackground oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.animated != widget.animated) {
      if (widget.animated) {
        _ctrl.repeat();
      } else {
        _ctrl.stop();
      }
    }
  }

  void _generateParticles() {
    final r = Random(27); // fixed seed for consistent look

    // Color palette close to your website look
    const palette = <Color>[
      Color(0xFF77E6FF), // cyan
      Color(0xFF8A7DFF), // lavender
      Color(0xFFFFC86B), // warm gold
      Color(0xFFFF78B4), // pink
      Color(0xFF72FFB0), // mint
    ];

    // Keep only 10 small stars (lightweight + matches your preference)
    _sparkles = List.generate(10, (i) {
      final c = palette[r.nextInt(palette.length)];
      final kind = r.nextDouble() < 0.65 ? _SparkleKind.sparkle4 : _SparkleKind.star5;
      return _Sparkle(
        x: r.nextDouble(),
        y: r.nextDouble(),
        // Smaller sparkles (avoid any "big" stars)
        size: lerpDouble(3.2, 5.4, r.nextDouble())!, // slightly bigger stars
        phase: r.nextDouble() * pi * 2,
        // Slightly faster twinkle range
        speed: lerpDouble(0.90, 1.90, r.nextDouble())!,
        baseAlpha: lerpDouble(0.35, 0.80, r.nextDouble())!,
        color: c,
        kind: kind,
      );
    });

    // Large outlined clouds (website-like banner shapes)
    _clouds = const [
      _Cloud(x: 0.00, y: 0.18, scale: 2.35, alpha: 0.14),
      _Cloud(x: 0.00, y: 0.80, scale: 2.55, alpha: 0.12),
    ];

    // Music notes + (very subtle) hearts sprinkled.
    // Keep these the same small scale as the stars to avoid large glyphs.
    _glyphs = [
      // Keep these small (similar feel to your website but not huge)
      const _Glyph(type: _GlyphType.note, x: 0.86, y: 0.20, size: 4, color: Color(0xFF8A7DFF)),
      const _Glyph(type: _GlyphType.note, x: 0.92, y: 0.28, size: 4, color: Color(0xFF77E6FF)),
      const _Glyph(type: _GlyphType.note, x: 0.80, y: 0.36, size: 3, color: Color(0xFFFF78B4)),
      const _Glyph(type: _GlyphType.note, x: 0.88, y: 0.44, size: 3, color: Color(0xFF77E6FF)),

      // One tiny heart only
      const _Glyph(type: _GlyphType.heart, x: 0.62, y: 0.50, size: 3, color: Color(0xFFFF78B4)),
    ];
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Respect accessibility reduce motion
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final animate = widget.animated && !reduceMotion;

    final darkTheme = Theme.of(context).brightness == Brightness.dark;
    final useDarkStyle = widget.forceDarkStyle ?? darkTheme;

    // IMPORTANT: Create the painter inside the AnimatedBuilder so 't' updates.
    // Otherwise, the background looks static.
    final repaint = animate
        ? AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              return CustomPaint(
                painter: _SkyPainter(
                  t: _ctrl.value,
                  sparkles: _sparkles,
                  clouds: _clouds,
                  glyphs: _glyphs,
                  darkStyle: useDarkStyle,
                ),
              );
            },
          )
        : CustomPaint(
            painter: _SkyPainter(
              t: 0.0,
              sparkles: _sparkles,
              clouds: _clouds,
              glyphs: _glyphs,
              darkStyle: useDarkStyle,
            ),
          );

    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(child: repaint),
        Container(color: Colors.black.withOpacity(widget.dimOpacity.clamp(0.0, 0.35))),
        widget.child,
      ],
    );
  }
}

/// Backward-compatible wrapper for screens that already use an image asset.
class BackgroundContainer extends StatelessWidget {
  final Widget child;
  final String imagePath;
  final double dimOpacity;

  const BackgroundContainer({
    super.key,
    required this.child,
    required this.imagePath,
    this.dimOpacity = 0.4,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(imagePath, fit: BoxFit.cover),
        Container(color: Colors.black.withOpacity(dimOpacity.clamp(0.0, 1.0))),
        child,
      ],
    );
  }
}

class _SkyPainter extends CustomPainter {
  final double t; // 0..1
  final List<_Sparkle> sparkles;
  final List<_Cloud> clouds;
  final List<_Glyph> glyphs;
  final bool darkStyle;

  _SkyPainter({
    required this.t,
    required this.sparkles,
    required this.clouds,
    required this.glyphs,
    required this.darkStyle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Background: deep navy -> indigo -> purple, slight diagonal feel like website
    final bg = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        // Slightly darker navy/purple base (closer to your website screenshot)
        colors: const [
          Color(0xFF020A22),
          Color(0xFF031133),
          Color(0xFF14062E),
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, bg);

    // NOTE: Removed large glow circles to avoid any "half-circle" artifacts.

    // Large faint cloud outlines
    for (final c in clouds) {
      _drawCloudOutline(canvas, size, c, t);
    }

    // Large website-like crescent moon (right side), gently pulsing + moving up/down
final moonPulse = 0.75 + 0.25 * sin((t * 2 * pi * 1.2) + 1.3);
final moonBob = sin((t * 2 * pi * 0.28) + 0.7) * size.height * 0.015;
_drawCrescentMoon(
  canvas,
  center: Offset(size.width * 0.90, size.height * 0.23 + moonBob),
  r: size.shortestSide * 0.20,
  // warm yellow stroke like the website
  stroke: const Color(0xFFFFD38A).withOpacity(0.16 + 0.12 * moonPulse),
);

    // Colorful sparkles/stars
    for (final s in sparkles) {
      final cx = s.x * size.width;
      final cy = s.y * size.height;

      final blink = (sin((t * 2 * pi * s.speed) + s.phase) + 1) * 0.5; // 0..1
      // more noticeable twinkle (dim -> bright) like the website
      final tw = 0.20 + 0.80 * blink; // 0.20..1.0
      final alpha = (s.baseAlpha * tw).clamp(0.10, 1.0);
      final scale = 0.88 + 0.22 * tw;

      final color = s.color.withOpacity(alpha);
      final glowColor = s.color.withOpacity(alpha * 0.30);

      // glow
      final glow = Paint()
        ..color = glowColor
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      // Slightly smaller glow so stars don't look like big blobs
      canvas.drawCircle(Offset(cx, cy), (s.size * 0.72) * scale, glow);

      // stroke sparkle
      final stroke = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      switch (s.kind) {
        case _SparkleKind.sparkle4:
          _drawSparkle4(canvas, Offset(cx, cy), s.size * scale, stroke);
          break;
        case _SparkleKind.star5:
          _drawStar5(canvas, Offset(cx, cy), s.size * 0.78 * scale, stroke);
          break;
      }
    }

    // Music notes + hearts + tiny sparkles
    for (final g in glyphs) {
      final o = Offset(g.x * size.width, g.y * size.height);

      // Faster rhythmic blink for icons (notes/hearts)
      final tw = 0.55 + 0.45 * sin((t * 2 * pi * 2.05) + (g.x + g.y) * 10);
      final alpha = (0.42 + 0.55 * tw).clamp(0.18, 0.95);

      final base = g.color.withOpacity(alpha);
      final glow = g.color.withOpacity(alpha * 0.25);

      // glow behind glyph
      final gp = Paint()..color = glow..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
      canvas.drawCircle(o, g.size * 0.70, gp);

      final stroke = Paint()
        ..color = base
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      switch (g.type) {
        case _GlyphType.note:
          _drawMusicNote(canvas, o, g.size.toDouble(), stroke);
          break;
        case _GlyphType.heart:
          _drawHeart(canvas, o, g.size.toDouble(), stroke);
          break;
        case _GlyphType.sparkleTiny:
          _drawSparkle4(canvas, o, g.size.toDouble(), stroke);
          break;
      }
    }
  }

  void _drawCloudOutline(Canvas canvas, Size size, _Cloud c, double t) {
  // Smooth left-right oscillation (no wrap/jump) + slight vertical bob
  final driftX = sin((t * 2 * pi * 0.10) + c.y * 2.4) * size.width * 0.09 * c.scale;
  final driftY = sin((t * 2 * pi * 0.08) + c.x * 4.1) * size.height * 0.008 * c.scale;

  final center = Offset(c.x * size.width + driftX, c.y * size.height + driftY);
  final w = size.width * 0.28 * c.scale;

  final pulse = 0.85 + 0.15 * sin((t * 2 * pi * 0.35) + c.x * 8);
  final alpha = (c.alpha * pulse).clamp(0.06, 0.22);

  final strokeColor = const Color(0xFF77E6FF).withOpacity(alpha);
  final glowColor = const Color(0xFF77E6FF).withOpacity(alpha * 0.35);

  // glow
  final glow = Paint()
    ..color = glowColor
    ..style = PaintingStyle.stroke
    ..strokeWidth = 10
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28);

  // stroke
  final stroke = Paint()
    ..color = strokeColor
    ..style = PaintingStyle.stroke
    ..strokeWidth = 4.0
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  final path = _foamyCloudPath(center: center, width: w);
  canvas.drawPath(path, glow);
  canvas.drawPath(path, stroke);
}

Path _foamyCloudPath({required Offset center, required double width}) {
  // "Foamy" cloud: more rounded bumps like the website background
  final w = width;
  final h = w * 0.42;

  final left = center.translate(-w * 0.60, 0);
  final path = Path()..moveTo(left.dx, left.dy);

  // top bumps (5 gentle bumps)
  path.cubicTo(
    left.dx + w * 0.10, left.dy - h * 0.85,
    left.dx + w * 0.28, left.dy - h * 0.95,
    left.dx + w * 0.36, left.dy - h * 0.48,
  );
  path.cubicTo(
    left.dx + w * 0.42, left.dy - h * 1.15,
    left.dx + w * 0.62, left.dy - h * 1.10,
    left.dx + w * 0.66, left.dy - h * 0.52,
  );
  path.cubicTo(
    left.dx + w * 0.72, left.dy - h * 0.98,
    left.dx + w * 0.92, left.dy - h * 0.82,
    left.dx + w * 0.92, left.dy - h * 0.20,
  );
  path.cubicTo(
    left.dx + w * 1.08, left.dy - h * 0.72,
    left.dx + w * 1.24, left.dy - h * 0.38,
    left.dx + w * 1.12, left.dy + h * 0.08,
  );

  // soft base
  path.quadraticBezierTo(
    left.dx + w * 1.00, left.dy + h * 0.48,
    left.dx + w * 0.74, left.dy + h * 0.36,
  );
  path.quadraticBezierTo(
    left.dx + w * 0.55, left.dy + h * 0.72,
    left.dx + w * 0.40, left.dy + h * 0.36,
  );
  path.quadraticBezierTo(
    left.dx + w * 0.18, left.dy + h * 0.42,
    left.dx + w * 0.12, left.dy + h * 0.22,
  );
  path.quadraticBezierTo(left.dx - w * 0.02, left.dy + h * 0.12, left.dx, left.dy);
  return path;
}

void _drawCrescentMoon(Canvas canvas, {required Offset center, required double r, required Color stroke}) {
    // outer glow
    final g = Paint()
      ..color = stroke.withOpacity(stroke.opacity * 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24);

    final p = Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final layerRect = Rect.fromCircle(center: center, radius: r * 1.9);
    canvas.saveLayer(layerRect, Paint());

    // draw full circle stroke then cut with clear circle to form crescent
    canvas.drawCircle(center, r, g);
    canvas.drawCircle(center, r, p);

    final cut = Paint()..blendMode = BlendMode.clear;
    canvas.drawCircle(center.translate(r * 0.45, -r * 0.05), r * 0.95, cut);

    canvas.restore();
  }

  void _drawSparkle4(Canvas canvas, Offset c, double size, Paint stroke) {
    // 4-point sparkle: two rotated diamonds
    final s = size;

    final path = Path();
    path.moveTo(c.dx, c.dy - s);
    path.lineTo(c.dx + s * 0.35, c.dy - s * 0.35);
    path.lineTo(c.dx + s, c.dy);
    path.lineTo(c.dx + s * 0.35, c.dy + s * 0.35);
    path.lineTo(c.dx, c.dy + s);
    path.lineTo(c.dx - s * 0.35, c.dy + s * 0.35);
    path.lineTo(c.dx - s, c.dy);
    path.lineTo(c.dx - s * 0.35, c.dy - s * 0.35);
    path.close();

    canvas.drawPath(path, stroke);
  }

  void _drawStar5(Canvas canvas, Offset c, double r, Paint stroke) {
    final path = Path();
    const points = 5;
    final angle = (2 * pi) / points;
    final halfAngle = angle / 2;

    for (int i = 0; i <= points; i++) {
      final a = -pi / 2 + angle * i;
      final outer = Offset(c.dx + r * cos(a), c.dy + r * sin(a));
      final inner = Offset(c.dx + (r * 0.45) * cos(a + halfAngle), c.dy + (r * 0.45) * sin(a + halfAngle));

      if (i == 0) {
        path.moveTo(outer.dx, outer.dy);
      } else {
        path.lineTo(outer.dx, outer.dy);
      }
      path.lineTo(inner.dx, inner.dy);
    }

    path.close();
    canvas.drawPath(path, stroke);
  }

  void _drawMusicNote(Canvas canvas, Offset o, double size, Paint stroke) {
    // A simple quaver-ish note using strokes (matches your website vibe)
    final stemTop = o.translate(0, -size * 0.55);
    final stemBot = o.translate(0, size * 0.35);
    canvas.drawLine(stemTop, stemBot, stroke);

    // flag
    final flag = Path()
      ..moveTo(stemTop.dx, stemTop.dy)
      ..quadraticBezierTo(stemTop.dx + size * 0.55, stemTop.dy + size * 0.15, stemTop.dx + size * 0.50, stemTop.dy + size * 0.48);
    canvas.drawPath(flag, stroke);

    // note head
    final head = Rect.fromCenter(
      center: stemBot.translate(size * 0.20, 0),
      width: size * 0.52,
      height: size * 0.36,
    );
    canvas.drawOval(head, stroke);
  }

  void _drawHeart(Canvas canvas, Offset c, double size, Paint stroke) {
    final s = size;
    final path = Path();

    path.moveTo(c.dx, c.dy + s * 0.35);
    path.cubicTo(
      c.dx - s * 0.75,
      c.dy - s * 0.10,
      c.dx - s * 0.35,
      c.dy - s * 0.85,
      c.dx,
      c.dy - s * 0.40,
    );
    path.cubicTo(
      c.dx + s * 0.35,
      c.dy - s * 0.85,
      c.dx + s * 0.75,
      c.dy - s * 0.10,
      c.dx,
      c.dy + s * 0.35,
    );

    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _SkyPainter oldDelegate) {
    return oldDelegate.t != t || oldDelegate.darkStyle != darkStyle;
  }
}

enum _SparkleKind { sparkle4, star5 }

enum _GlyphType { note, heart, sparkleTiny }

class _Sparkle {
  final double x, y;
  final double size;
  final double phase;
  final double speed;
  final double baseAlpha;
  final Color color;
  final _SparkleKind kind;

  _Sparkle({
    required this.x,
    required this.y,
    required this.size,
    required this.phase,
    required this.speed,
    required this.baseAlpha,
    required this.color,
    required this.kind,
  });
}

class _Cloud {
  final double x, y;
  final double scale;
  final double alpha;

  const _Cloud({
    required this.x,
    required this.y,
    required this.scale,
    required this.alpha,
  });
}

class _Glyph {
  final _GlyphType type;
  final double x, y;
  final int size;
  final Color color;

  const _Glyph({
    required this.type,
    required this.x,
    required this.y,
    required this.size,
    required this.color,
  });
}
