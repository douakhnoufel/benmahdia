import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/capture_scrim.dart';
import 'verification_models.dart';
import 'verification_widgets.dart';

/// Step 2 of the identity check: front then back of the national ID card.
/// A scan line sweeps the card frame until a whole card is found; then the
/// corners turn green, "card detected" pops in and the shutter wakes up.
/// After the front, the screen flips to the back by itself.
class IdCaptureScreen extends StatefulWidget {
  const IdCaptureScreen({
    super.key,
    required this.cardDetected,
    required this.onDone,
  });

  /// Completes once a whole card is steady in the frame; called again for
  /// each side. A demo timer today, the on-device detector later.
  final Future<void> Function() cardDetected;

  /// Called once both sides are captured.
  final VoidCallback onDone;

  @override
  State<IdCaptureScreen> createState() => _IdCaptureScreenState();
}

class _IdCaptureScreenState extends State<IdCaptureScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scan = AnimationController(
    vsync: this,
    duration: AppMotion.scan,
  );
  final _captured = <CardSide>{};
  CardSide _side = CardSide.front;
  bool _detected = false;
  bool _reduced = false;
  int _watch = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_lookForCard());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = AppMotion.reduced(context);
    _syncScan();
  }

  void _syncScan() {
    if (_reduced || _detected) {
      _scan.stop();
    } else if (!_scan.isAnimating) {
      unawaited(_scan.repeat(reverse: true));
    }
  }

  Future<void> _lookForCard() async {
    final watch = ++_watch;
    await widget.cardDetected();
    // Ignore a result for a side the user has already moved away from.
    if (!mounted || watch != _watch) return;
    setState(() => _detected = true);
    _syncScan();
  }

  void _show(CardSide side) {
    if (side == _side) return;
    setState(() {
      _side = side;
      _detected = false;
    });
    _syncScan();
    unawaited(_lookForCard());
  }

  void _capture() {
    if (!_detected) return;
    setState(() => _captured.add(_side));
    final missing = CardSide.values.where((s) => !_captured.contains(s));
    if (missing.isEmpty) {
      widget.onDone();
    } else {
      _show(missing.first);
    }
  }

  @override
  void dispose() {
    _scan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final medium = AppMotion.of(context, AppMotion.medium);
    final front = _side == CardSide.front;
    final place = front ? l10n.idPlaceFront : l10n.idPlaceBack;

    return Scaffold(
      backgroundColor: AppColors.teal900,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final frame = _frameFor(size);
          return Stack(
            children: [
              const Positioned.fill(child: CameraPlaceholder()),
              Positioned.fill(
                child: CustomPaint(painter: CaptureScrimPainter(hole: frame)),
              ),
              Positioned.fromRect(
                rect: frame,
                child: _CardFrame(
                  scan: _scan,
                  detected: _detected,
                  scanning: !_reduced,
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: frame.top - AppSpace.md,
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      FlowTopBar(
                        title: l10n.idTitle,
                        step: 2,
                        total: 3,
                        onDark: true,
                      ),
                      const SizedBox(height: AppSpace.lg),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpace.screenHorizontal,
                        ),
                        child: _SideSwitch(
                          side: _side,
                          captured: _captured,
                          onChanged: _show,
                        ),
                      ),
                      const SizedBox(height: AppSpace.md),
                      AnimatedSwitcher(
                        duration: medium,
                        child: Text(
                          place,
                          key: ValueKey(place),
                          textAlign: TextAlign.center,
                          style: text.bodyLarge?.copyWith(
                            color: AppColors.onPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: frame.bottom + AppSpace.lg,
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpace.screenHorizontal,
                      0,
                      AppSpace.screenHorizontal,
                      AppSpace.lg,
                    ),
                    child: Column(
                      children: [
                        AnimatedSwitcher(
                          duration: medium,
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: ScaleTransition(
                                  scale: animation.drive(
                                    Tween<double>(
                                      begin: 0.85,
                                      end: 1,
                                    ).chain(CurveTween(curve: AppMotion.pop)),
                                  ),
                                  child: child,
                                ),
                              ),
                          child: _detected
                              ? CameraStatusPill(
                                  key: const ValueKey('detected'),
                                  label: l10n.idDetected,
                                  icon: Icons.check_rounded,
                                  color: AppColors.success,
                                )
                              : CameraStatusPill(
                                  key: const ValueKey('searching'),
                                  label: l10n.idSearching,
                                  icon: Icons.center_focus_weak_rounded,
                                  color: AppColors.sand300,
                                ),
                        ),
                        const SizedBox(height: AppSpace.lg),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              children: [
                                _Tip(
                                  icon: Icons.crop_landscape_rounded,
                                  text: l10n.idTipSurface,
                                ),
                                _Tip(
                                  icon: Icons.wb_sunny_outlined,
                                  text: l10n.idTipGlare,
                                ),
                                _Tip(
                                  icon: Icons.crop_free_rounded,
                                  text: l10n.idTipCorners,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpace.md),
                        _Shutter(
                          enabled: _detected,
                          label: front
                              ? l10n.idCaptureFront
                              : l10n.idCaptureBack,
                          onPressed: _capture,
                        ),
                        const SizedBox(height: AppSpace.md),
                        PrivacyLine(text: l10n.idPrivacy, onDark: true),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Card frame: ID-1 proportions, centred a little above the middle.
Rect _frameFor(Size size) {
  final width = math.min(
    size.width - AppSpace.xl * 2,
    size.height * 0.30 * _cardAspect,
  );
  return Rect.fromCenter(
    center: Offset(size.width / 2, size.height * 0.44),
    width: width,
    height: width / _cardAspect,
  );
}

/// ISO/IEC 7810 ID-1 card, 85.6 × 54 mm.
const _cardAspect = 85.6 / 54;

class _CardFrame extends StatelessWidget {
  const _CardFrame({
    required this.scan,
    required this.detected,
    required this.scanning,
  });

  final Animation<double> scan;
  final bool detected;
  final bool scanning;

  @override
  Widget build(BuildContext context) {
    final medium = AppMotion.of(context, AppMotion.medium);
    return ExcludeSemantics(
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(
          end: detected ? AppColors.success : AppColors.teal500,
        ),
        duration: medium,
        builder: (context, color, line) => CustomPaint(
          foregroundPainter: _CornersPainter(
            color: color ?? AppColors.teal500,
            radius: AppRadius.card,
          ),
          child: line,
        ),
        child: scanning
            ? AnimatedOpacity(
                opacity: detected ? 0 : 1,
                duration: medium,
                child: AnimatedBuilder(
                  animation: scan,
                  builder: (context, line) => Align(
                    alignment: Alignment(0, scan.value * 2 - 1),
                    child: line,
                  ),
                  child: const _ScanLine(),
                ),
              )
            : const SizedBox.expand(),
      ),
    );
  }
}

class _ScanLine extends StatelessWidget {
  const _ScanLine();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
      child: SizedBox(
        height: 2,
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.teal300.withValues(alpha: 0),
                AppColors.teal300,
                AppColors.teal300.withValues(alpha: 0),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.teal300.withValues(alpha: 0.6),
                blurRadius: AppSpace.md,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CornersPainter extends CustomPainter {
  const _CornersPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final length = math.min(size.shortestSide * 0.2, 36.0);
    final corner = Path()
      ..moveTo(0, length)
      ..lineTo(0, radius)
      ..arcToPoint(Offset(radius, 0), radius: Radius.circular(radius))
      ..lineTo(length, 0);
    for (final (sx, sy) in const [
      (1.0, 1.0),
      (-1.0, 1.0),
      (1.0, -1.0),
      (-1.0, -1.0),
    ]) {
      canvas
        ..save()
        ..translate(sx > 0 ? 0 : size.width, sy > 0 ? 0 : size.height)
        ..scale(sx, sy)
        ..drawPath(corner, paint)
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_CornersPainter old) =>
      old.color != color || old.radius != radius;
}

/// Front / back switch on the dark camera screen. The white thumb slides to
/// the side being captured; a captured side shows a check.
class _SideSwitch extends StatelessWidget {
  const _SideSwitch({
    required this.side,
    required this.captured,
    required this.onChanged,
  });

  final CardSide side;
  final Set<CardSide> captured;
  final ValueChanged<CardSide> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.all(AppSpace.xs),
      decoration: BoxDecoration(
        color: AppColors.teal800,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedAlign(
              duration: AppMotion.of(context, AppMotion.medium),
              curve: AppMotion.curve,
              alignment: AlignmentDirectional(
                side == CardSide.front ? -1 : 1,
                0,
              ),
              child: FractionallySizedBox(
                widthFactor: 0.5,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (final s in CardSide.values)
                _SideSegment(
                  label: s == CardSide.front ? l10n.idFront : l10n.idBack,
                  selected: s == side,
                  captured: captured.contains(s),
                  onTap: () => onChanged(s),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SideSegment extends StatelessWidget {
  const _SideSegment({
    required this.label,
    required this.selected,
    required this.captured,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool captured;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.teal700 : AppColors.teal100;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        checked: captured,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedScale(
                  scale: captured ? 1 : 0,
                  duration: AppMotion.of(context, AppMotion.medium),
                  curve: AppMotion.pop,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(end: AppSpace.xs),
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 16,
                      color: selected ? AppColors.success : AppColors.teal300,
                    ),
                  ),
                ),
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: color,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.teal300),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.teal50),
            ),
          ),
        ],
      ),
    );
  }
}

/// Round shutter. Dimmed and inert until a card is detected, then it grows
/// back to full size.
class _Shutter extends StatelessWidget {
  const _Shutter({
    required this.enabled,
    required this.label,
    required this.onPressed,
  });

  final bool enabled;
  final String label;
  final VoidCallback onPressed;

  static const _size = 76.0;

  @override
  Widget build(BuildContext context) {
    final medium = AppMotion.of(context, AppMotion.medium);
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: enabled ? onPressed : null,
        child: AnimatedOpacity(
          opacity: enabled ? 1 : 0.4,
          duration: medium,
          child: AnimatedScale(
            scale: enabled ? 1 : 0.9,
            duration: medium,
            curve: AppMotion.pop,
            child: Container(
              width: _size,
              height: _size,
              padding: const EdgeInsets.all(AppSpace.xs + 1),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.onPrimary, width: 4),
              ),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.onPrimary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
