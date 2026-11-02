import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

/// The splash look: the clinic's blue logo on the Argon blue palette.
abstract final class _Look {
  static const logoAsset = 'assets/brand/logo.png';
  static const bgTop = AppColors.argonBgTop;
  static const bgBottom = AppColors.argonBgBottom;
  static const accent = AppColors.argonBlue;
  static const ink = AppColors.argonInk;
}

/// Splash-only measurements from the Argon launch spec. Kept here, in one
/// place, rather than scattered through the widget tree.
abstract final class _Splash {
  static const logoSize = 180.0;
  static const cardRadius = 32.0;
  static const cardPadding = AppSpace.xxl;
  static const glassBlur = 16.0;
  static const glassFill = 0.65;
  static const glassBorder = 0.80;
  static const glassBorderWidth = 1.5;
  static const titleSize = 24.0;
  static const titleTracking = 6.0;
  static const titleRise = 20.0;
  static const accentWidth = 40.0;
  static const accentHeight = 4.0;
  static const breathLift = 4.0;

  /// Entrance timeline: 0 → 1.8 s, then the calm breathing hold.
  static const intro = Duration(milliseconds: 1800);
  static const breath = Duration(milliseconds: 3200);
  static const bubbleCycle = Duration(milliseconds: 5200);
  static const fadeOut = Duration(milliseconds: 600);

  static const minDuration = Duration(seconds: 3);
  static const maxDuration = Duration(seconds: 5);
}

/// Launch splash in the Argon style: a frosted glass card on a soft
/// gradient, the logo with small bubbles floating up beside it, and the
/// "LIFE QUALITY" title.
///
/// It stays for [splashDuration] (clamped to 3–5 s) and, if given, until
/// [ready] completes — whichever is later — then calls [onFinish], or fades
/// to [nextScreen] when no callback is given. With reduced motion turned on
/// in the OS, everything is shown at once and nothing loops.
class LifeQualitySplashScreen extends StatefulWidget {
  const LifeQualitySplashScreen({
    super.key,
    this.splashDuration = const Duration(seconds: 4),
    this.ready,
    this.onFinish,
    this.nextScreen,
  }) : assert(
         onFinish != null || nextScreen != null,
         'Give onFinish or nextScreen',
       );

  final Duration splashDuration;

  /// Startup work to wait for (restoring the session…). Must not fail.
  final Future<void>? ready;
  final VoidCallback? onFinish;
  final Widget? nextScreen;

  @override
  State<LifeQualitySplashScreen> createState() =>
      _LifeQualitySplashScreenState();
}

class _LifeQualitySplashScreenState extends State<LifeQualitySplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: _Splash.intro,
  );
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: _Splash.breath,
  );
  late final AnimationController _bubbles = AnimationController(
    vsync: this,
    duration: _Splash.bubbleCycle,
  );

  // 0.0–1.2 s: card and logo scale 0.85 → 1.0 and fade in.
  late final Animation<double> _cardScale = Tween(begin: 0.85, end: 1.0)
      .animate(
        CurvedAnimation(
          parent: _intro,
          curve: const Interval(0, 1.2 / 1.8, curve: Curves.easeOutBack),
        ),
      );
  late final Animation<double> _cardFade = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0, 1.2 / 1.8, curve: Curves.easeOut),
  );

  // 0.4–1.5 s: bubbles fade in.
  late final Animation<double> _bubbleFade = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.4 / 1.8, 1.5 / 1.8, curve: Curves.easeInOutSine),
  );

  // 0.8–1.8 s: title slides up 20 px and fades in.
  late final Animation<double> _title = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.8 / 1.8, 1.0, curve: Curves.easeOutCubic),
  );

  bool _started = false;
  bool _finished = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Follows the OS setting, also if it changes while the splash is up.
    if (AppMotion.reduced(context)) {
      _intro.value = 1;
      _breath.stop();
      _bubbles.stop();
    } else if (!_bubbles.isAnimating) {
      if (!_intro.isCompleted) unawaited(_intro.forward());
      unawaited(_breath.repeat(reverse: true));
      unawaited(_bubbles.repeat());
    }
    if (_started) return;
    _started = true;
    unawaited(_finish());
  }

  Duration get _duration {
    final d = widget.splashDuration;
    if (d < _Splash.minDuration) return _Splash.minDuration;
    if (d > _Splash.maxDuration) return _Splash.maxDuration;
    return d;
  }

  Future<void> _finish() async {
    await Future.wait([
      Future<void>.delayed(_duration),
      if (widget.ready != null) widget.ready!,
    ]);
    if (!mounted || _finished) return;
    _finished = true;
    final onFinish = widget.onFinish;
    if (onFinish != null) {
      onFinish();
      return;
    }
    final next = widget.nextScreen!;
    unawaited(
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          transitionDuration: AppMotion.of(context, _Splash.fadeOut),
          pageBuilder: (_, _, _) => next,
          transitionsBuilder: (_, animation, _, child) => FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOutSine,
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _intro.dispose();
    _breath.dispose();
    _bubbles.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Look.bgTop,
      body: Semantics(
        label: 'LIFE QUALITY',
        container: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_Look.bgTop, _Look.bgBottom],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _AmbientCircles(accent: _Look.accent),
              SafeArea(
                child: Center(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_intro, _breath]),
                    builder: (context, child) {
                      final breath = Curves.easeInOutSine.transform(
                        _breath.value,
                      );
                      return Opacity(
                        opacity: _cardFade.value.clamp(0.0, 1.0),
                        child: Transform.scale(
                          scale: _cardScale.value,
                          child: Transform.translate(
                            offset: Offset(
                              0,
                              (0.5 - breath) * 2 * _Splash.breathLift,
                            ),
                            child: child,
                          ),
                        ),
                      );
                    },
                    child: _GlassCard(
                      accent: _Look.accent,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _LogoWithBubbles(
                            asset: _Look.logoAsset,
                            accent: _Look.accent,
                            bubbles: _bubbles,
                            fade: _bubbleFade,
                          ),
                          const SizedBox(height: AppSpace.xl),
                          _Title(
                            progress: _title,
                            ink: _Look.ink,
                            accent: _Look.accent,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Soft blobs behind the card in the accent colour. Decorative.
class _AmbientCircles extends StatelessWidget {
  const _AmbientCircles({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    Widget circle(double size, double alpha) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            accent.withValues(alpha: alpha),
            accent.withValues(alpha: 0),
          ],
        ),
      ),
    );

    return ExcludeSemantics(
      child: Stack(
        children: [
          Positioned(top: -80, left: -60, child: circle(260, 0.14)),
          Positioned(top: 140, right: -90, child: circle(220, 0.10)),
          Positioned(bottom: -100, left: 30, child: circle(300, 0.12)),
        ],
      ),
    );
  }
}

/// Frosted glass: blur behind, translucent white fill, bright hairline
/// border, and two layers of soft ambient shadow in the accent colour.
class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.accent, required this.child});

  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(_Splash.cardRadius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.15),
            offset: const Offset(0, 24),
            blurRadius: 48,
          ),
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            offset: const Offset(0, 6),
            blurRadius: 14,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: _Splash.glassBlur,
            sigmaY: _Splash.glassBlur,
          ),
          child: Container(
            padding: const EdgeInsets.all(_Splash.cardPadding),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: _Splash.glassFill),
              borderRadius: radius,
              border: Border.all(
                color: AppColors.surface.withValues(alpha: _Splash.glassBorder),
                width: _Splash.glassBorderWidth,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _LogoWithBubbles extends StatelessWidget {
  const _LogoWithBubbles({
    required this.asset,
    required this.accent,
    required this.bubbles,
    required this.fade,
  });

  final String asset;
  final Color accent;
  final Animation<double> bubbles;
  final Animation<double> fade;

  @override
  Widget build(BuildContext context) {
    Widget logo(String path) => Image.asset(
      path,
      width: _Splash.logoSize,
      height: _Splash.logoSize,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
    );

    return SizedBox(
      width: _Splash.logoSize + AppSpace.xxxl,
      height: _Splash.logoSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          logo(asset),
          Positioned.fill(
            child: ExcludeSemantics(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _BubblePainter(
                    cycle: bubbles,
                    fade: fade,
                    accent: accent,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One bubble: where it starts (as a fraction of the box), its size, and
/// where in the shared cycle it sits, so they never move in step.
class _Bubble {
  const _Bubble(this.x, this.y, this.radius, this.phase, {this.white = false});

  final double x;
  final double y;
  final double radius;
  final double phase;
  final bool white;
}

/// Twelve bubbles on the right side of the logo, drifting up with a small
/// sideways sway and fading in and out at the ends of their path.
class _BubblePainter extends CustomPainter {
  _BubblePainter({
    required this.cycle,
    required this.fade,
    required this.accent,
  }) : super(repaint: Listenable.merge([cycle, fade]));

  final Animation<double> cycle;
  final Animation<double> fade;
  final Color accent;

  static const _bubbles = [
    _Bubble(0.70, 0.78, 3.5, 0.00),
    _Bubble(0.78, 0.66, 2.5, 0.12, white: true),
    _Bubble(0.84, 0.82, 4.5, 0.25),
    _Bubble(0.74, 0.55, 2.0, 0.33, white: true),
    _Bubble(0.90, 0.70, 3.0, 0.41),
    _Bubble(0.80, 0.90, 2.5, 0.50, white: true),
    _Bubble(0.94, 0.58, 2.0, 0.58),
    _Bubble(0.68, 0.64, 3.0, 0.66, white: true),
    _Bubble(0.87, 0.48, 3.5, 0.74),
    _Bubble(0.76, 0.74, 2.0, 0.81, white: true),
    _Bubble(0.92, 0.86, 3.0, 0.88),
    _Bubble(0.82, 0.60, 2.5, 0.95, white: true),
  ];

  /// How far a bubble rises over one cycle, as a fraction of the box height.
  static const _travel = 0.45;

  @override
  void paint(Canvas canvas, Size size) {
    final appear = fade.value.clamp(0.0, 1.0);
    if (appear == 0) return;
    final t = cycle.value;
    final fill = Paint()..style = PaintingStyle.fill;
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (final b in _bubbles) {
      final p = (t + b.phase) % 1.0;
      // Fade in at the bottom of the path and out at the top.
      final alpha = appear * math.sin(p * math.pi);
      if (alpha <= 0) continue;
      final dx = math.sin(p * 2 * math.pi + b.phase * 6) * 3;
      final center = Offset(
        b.x * size.width + dx,
        (b.y - p * _travel) * size.height,
      );
      if (b.white) {
        fill.color = AppColors.surface.withValues(alpha: 0.85 * alpha);
        rim.color = accent.withValues(alpha: 0.45 * alpha);
        canvas
          ..drawCircle(center, b.radius, fill)
          ..drawCircle(center, b.radius, rim);
      } else {
        fill.color = accent.withValues(alpha: 0.70 * alpha);
        canvas.drawCircle(center, b.radius, fill);
      }
    }
  }

  @override
  bool shouldRepaint(_BubblePainter old) =>
      old.cycle != cycle || old.fade != fade || old.accent != accent;
}

class _Title extends StatelessWidget {
  const _Title({
    required this.progress,
    required this.ink,
    required this.accent,
  });

  final Animation<double> progress;
  final Color ink;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: progress,
      builder: (context, child) {
        final v = progress.value.clamp(0.0, 1.0);
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, (1 - v) * _Splash.titleRise),
            child: child,
          ),
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'LIFE QUALITY',
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
            style: TextStyle(
              color: ink,
              fontSize: _Splash.titleSize,
              fontWeight: FontWeight.w700,
              letterSpacing: _Splash.titleTracking,
            ),
          ),
          const SizedBox(height: AppSpace.md),
          Container(
            width: _Splash.accentWidth,
            height: _Splash.accentHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              gradient: LinearGradient(
                colors: [accent, accent.withValues(alpha: 0.35)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
