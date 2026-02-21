import 'dart:math';
import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';

/// Centralized App background that matches appayistories.com vibe:
/// - Blue gradient night-sky
/// - Soft twinkling stars (optional)
/// - Subtle clouds + music notes shapes
///
/// You can use it per-screen:
///   return AppBackground(child: Scaffold(...));
///
/// Or globally (recommended gradual rollout):
///   MaterialApp(builder: (context, child) => AppBackground(child: child ?? SizedBox()));
///
/// NOTE: For global usage, screens with Scaffold backgrounds will still cover it unless
/// their Scaffold backgroundColor is transparent.
class AppBackground extends StatefulWidget {
  final Widget child;

  /// If false, paints a static background (zero animation work).
  final bool animated;

  /// Dark overlay to improve contrast with foreground UI.
  final double dimOpacity;

  /// If you want to force a specific style regardless of theme.
  final bool? forceDarkStyle;

  const AppBackground({
    Key? key,
    required this.child,
    this.animated = true,
    this.dimOpacity = 0.10,
    this.forceDarkStyle,
  }) : super(key: key);

  @override
  State<AppBackground> createState() => _AppBackgroundState();
}

class _AppBackgroundState extends State<AppBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  // Pre-generated particles so they don't shift each frame
  late final List<_Star> _stars;
  late final List<_Cloud> _clouds;
  late final List<_Note> _notes;

  @override
  void initState() {
    super.initState();

    _generateParticles();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
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
    final r = Random(42); // fixed seed for consistent look

    _stars = List.generate(44, (_) {
      return _Star(
        x: r.nextDouble(),
        y: r.nextDouble(),
        radius: lerpDouble(0.7, 1.9, r.nextDouble())!,
        phase: r.nextDouble() * pi * 2,
        speed: lerpDouble(0.6, 1.6, r.nextDouble())!,
        baseAlpha: lerpDouble(0.15, 0.45, r.nextDouble())!,
      );
    });

    _clouds = [
      _Cloud(x: 0.18, y: 0.78, scale: 1.15, alpha: 0.10),
      _Cloud(x: 0.62, y: 0.86, scale: 1.35, alpha: 0.08),
      _Cloud(x: 0.86, y: 0.74, scale: 0.95, alpha: 0.10),
    ];

    _notes = [
      _Note(x: 0.82, y: 0.20, size: 16),
      _Note(x: 0.90, y: 0.30, size: 14),
      _Note(x: 0.76, y: 0.34, size: 12),
      _Note(x: 0.86, y: 0.42, size: 13),
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

    final repaint = animate ? AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return CustomPaint(
          painter: _SkyPainter(
            t: _ctrl.value,
            stars: _stars,
            clouds: _clouds,
            notes: _notes,
            darkStyle: useDarkStyle,
          ),
        );
      },
    ) : CustomPaint(
      painter: _SkyPainter(
        t: 0.0,
        stars: _stars,
        clouds: _clouds,
        notes: _notes,
        darkStyle: useDarkStyle,
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        // Paint background in its own repaint boundary
        RepaintBoundary(child: repaint),

        // Dim overlay for contrast (kept light so content still feels airy)
        Container(
          color: Colors.black.withOpacity(widget.dimOpacity.clamp(0.0, 0.35)),
        ),

        // Foreground UI
        widget.child,
      ],
    );
  }
}

/// Backward-compatible wrapper for screens that already use an image asset.
/// If you want the new central background, prefer [AppBackground].
class BackgroundContainer extends StatelessWidget {
  final Widget child;
  final String imagePath;
  final double dimOpacity;

  const BackgroundContainer({
    Key? key,
    required this.child,
    required this.imagePath,
    this.dimOpacity = 0.4,
  }) : super(key: key);

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
  final List<_Star> stars;
  final List<_Cloud> clouds;
  final List<_Note> notes;
  final bool darkStyle;

  _SkyPainter({
    required this.t,
    required this.stars,
    required this.clouds,
    required this.notes,
    required this.darkStyle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Gradient background
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: darkStyle
            ? const [
                Color(0xFF061A3A), // deep navy
                Color(0xFF0B2B66), // rich blue
                Color(0xFF10142B), // night violet
              ]
            : const [
                Color(0xFF0B4FA3), // bright sky blue
                Color(0xFF123B7A), // mid blue
                Color(0xFF1A2150), // dusk
              ],
        stops: const [0.0, 0.6, 1.0],
      ).createShader(rect);

    canvas.drawRect(rect, bgPaint);

    // Soft glow blob (top-left) like website
    final glow = Paint()
      ..color = (darkStyle ? const Color(0xFF5E8CFF) : const Color(0xFF9CC7FF)).withOpacity(0.10)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40);
    canvas.drawCircle(Offset(size.width * 0.15, size.height * 0.10), size.shortestSide * 0.35, glow);

    // Stars
    for (final s in stars) {
      final x = s.x * size.width;
      final y = s.y * size.height;

      // twinkle
      final tw = 0.55 + 0.45 * sin((t * 2 * pi * s.speed) + s.phase);
      final alpha = (s.baseAlpha * tw).clamp(0.05, 0.65);

      final p = Paint()..color = Colors.white.withOpacity(alpha);
      canvas.drawCircle(Offset(x, y), s.radius, p);

      // A few stars get a tiny glow
      if (s.radius > 1.5) {
        final g = Paint()
          ..color = Colors.white.withOpacity(alpha * 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
        canvas.drawCircle(Offset(x, y), s.radius * 2.2, g);
      }
    }

    // Clouds (soft ovals)
    final cloudPaint = Paint()
      ..color = Colors.white.withOpacity(darkStyle ? 0.09 : 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);

    for (final c in clouds) {
      final cx = c.x * size.width;
      final cy = c.y * size.height;
      final s = c.scale;

      _drawCloud(canvas, cloudPaint..color = cloudPaint.color.withOpacity(c.alpha), Offset(cx, cy), size.width * 0.22 * s);
    }

    // Music notes (subtle)
    final noteColor = Colors.white.withOpacity(darkStyle ? 0.12 : 0.16);
    for (final n in notes) {
      final nx = n.x * size.width;
      final ny = n.y * size.height;

      _drawMusicNote(canvas, Offset(nx, ny), n.size.toDouble(), noteColor);
    }
  }

  void _drawCloud(Canvas canvas, Paint paint, Offset center, double w) {
    final h = w * 0.42;
    final r1 = Rect.fromCenter(center: center.translate(-w * 0.15, 0), width: w * 0.80, height: h);
    final r2 = Rect.fromCenter(center: center.translate(w * 0.15, -h * 0.10), width: w * 0.70, height: h * 0.92);
    final r3 = Rect.fromCenter(center: center.translate(0, -h * 0.20), width: w * 0.55, height: h * 0.80);

    canvas.drawOval(r1, paint);
    canvas.drawOval(r2, paint);
    canvas.drawOval(r3, paint);
  }

  void _drawMusicNote(Canvas canvas, Offset o, double size, Color color) {
    final p = Paint()
      ..color = color
      ..strokeWidth = size * 0.10
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // stem
    final stemTop = o.translate(0, -size * 0.35);
    final stemBot = o.translate(0, size * 0.25);
    canvas.drawLine(stemTop, stemBot, p);

    // flag
    final flag1 = stemTop.translate(size * 0.28, size * 0.10);
    canvas.drawLine(stemTop, flag1, p);

    // note head
    final head = Paint()..color = color.withOpacity(0.9);
    canvas.drawOval(
      Rect.fromCenter(center: stemBot.translate(size * 0.12, 0), width: size * 0.42, height: size * 0.30),
      head,
    );
  }

  @override
  bool shouldRepaint(covariant _SkyPainter oldDelegate) {
    return oldDelegate.t != t || oldDelegate.darkStyle != darkStyle;
  }
}

class _Star {
  final double x, y;
  final double radius;
  final double phase;
  final double speed;
  final double baseAlpha;

  _Star({
    required this.x,
    required this.y,
    required this.radius,
    required this.phase,
    required this.speed,
    required this.baseAlpha,
  });
}

class _Cloud {
  final double x, y;
  final double scale;
  final double alpha;

  _Cloud({
    required this.x,
    required this.y,
    required this.scale,
    required this.alpha,
  });
}

class _Note {
  final double x, y;
  final int size;

  _Note({
    required this.x,
    required this.y,
    required this.size,
  });
}
