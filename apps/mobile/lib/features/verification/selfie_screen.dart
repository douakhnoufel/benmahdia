import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/capture_scrim.dart';
import 'verification_models.dart';
import 'verification_widgets.dart';

/// Step 1 of the identity check: a live selfie with a liveness check. A pulse
/// breathes around the face oval while a ring fills one third per completed
/// step; when all are done the ring turns green, a check pops in and
/// [onCaptured] is called. The photo is taken live only (no gallery, PRD 4.2).
class SelfieScreen extends StatefulWidget {
  const SelfieScreen({
    super.key,
    required this.steps,
    required this.onCaptured,
  });

  /// Emits each liveness step as the user completes it.
  final Stream<LivenessStep> steps;
  final VoidCallback onCaptured;

  @override
  State<SelfieScreen> createState() => _SelfieScreenState();
}

class _SelfieScreenState extends State<SelfieScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: AppMotion.pulse,
  );
  late final StreamSubscription<LivenessStep> _steps;
  final _done = <LivenessStep>{};
  Timer? _advance;
  bool _reduced = false;

  bool get _captured => _done.length == LivenessStep.values.length;

  LivenessStep? get _current =>
      LivenessStep.values.where((s) => !_done.contains(s)).firstOrNull;

  @override
  void initState() {
    super.initState();
    _steps = widget.steps.listen(_onStep);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = AppMotion.reduced(context);
    _syncPulse();
  }

  void _syncPulse() {
    if (_reduced || _captured) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      unawaited(_pulse.repeat());
    }
  }

  void _onStep(LivenessStep step) {
    setState(() => _done.add(step));
    if (!_captured) return;
    _syncPulse();
    // Let the green ring and check register before moving on.
    _advance = Timer(AppMotion.slow * 2, widget.onCaptured);
  }

  void _continue() {
    _advance?.cancel();
    widget.onCaptured();
  }

  @override
  void dispose() {
    _advance?.cancel();
    unawaited(_steps.cancel());
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final current = _current;

    return Scaffold(
      backgroundColor: AppColors.teal900,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final oval = _ovalFor(size);
          return Stack(
            children: [
              const Positioned.fill(child: CameraPlaceholder()),
              Positioned.fill(
                child: CustomPaint(
                  painter: CaptureScrimPainter(hole: oval, oval: true),
                ),
              ),
              Positioned.fromRect(
                rect: oval.inflate(_ringGap),
                child: _LivenessRing(
                  pulse: _pulse,
                  progress: _done.length / LivenessStep.values.length,
                  captured: _captured,
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: oval.top - _ringGap,
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      FlowTopBar(
                        title: l10n.verifyTitle,
                        step: 1,
                        total: 3,
                        onDark: true,
                      ),
                      const SizedBox(height: AppSpace.lg),
                      Text(
                        l10n.selfieTitle,
                        textAlign: TextAlign.center,
                        style: text.headlineMedium?.copyWith(
                          color: AppColors.onPrimary,
                        ),
                      ),
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        l10n.selfieHint,
                        textAlign: TextAlign.center,
                        style: text.bodySmall?.copyWith(
                          color: AppColors.teal100,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: oval.bottom + _ringGap + AppSpace.md,
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
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              children: [
                                AnimatedSwitcher(
                                  duration: AppMotion.of(
                                    context,
                                    AppMotion.medium,
                                  ),
                                  child: current == null
                                      ? CameraStatusPill(
                                          key: const ValueKey('captured'),
                                          label: l10n.selfieCaptured,
                                          icon: Icons.check_rounded,
                                          color: AppColors.success,
                                        )
                                      : CameraStatusPill(
                                          key: ValueKey(current),
                                          label: _instruction(l10n, current),
                                          icon: _icon(current),
                                          color: AppColors.sand400,
                                        ),
                                ),
                                const SizedBox(height: AppSpace.md),
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: AppSpace.sm,
                                  runSpacing: AppSpace.sm,
                                  children: [
                                    for (final step in LivenessStep.values)
                                      _StepChip(
                                        label: _instruction(l10n, step),
                                        state: _done.contains(step)
                                            ? _ChipState.done
                                            : step == current
                                            ? _ChipState.active
                                            : _ChipState.pending,
                                      ),
                                  ],
                                ),
                                if (!_captured) ...[
                                  const SizedBox(height: AppSpace.md),
                                  Text(
                                    l10n.selfieAuto,
                                    textAlign: TextAlign.center,
                                    style: text.bodyMedium?.copyWith(
                                      color: AppColors.teal50,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        if (_captured) ...[
                          const SizedBox(height: AppSpace.md),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _continue,
                              child: Text(l10n.verifyContinue),
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpace.md),
                        PrivacyLine(text: l10n.selfiePrivacy, onDark: true),
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

/// Face oval: centred a little above the middle, as tall as the screen allows.
Rect _ovalFor(Size size) {
  final height = math.min(size.height * 0.36, size.width * 0.62 * _ovalAspect);
  return Rect.fromCenter(
    center: Offset(size.width / 2, size.height * 0.46),
    width: height / _ovalAspect,
    height: height,
  );
}

const _ovalAspect = 1.28;

IconData _icon(LivenessStep step) => switch (step) {
  LivenessStep.lookAtCamera => Icons.center_focus_strong_rounded,
  LivenessStep.turnHead => Icons.swap_horiz_rounded,
  LivenessStep.blink => Icons.visibility_rounded,
};
const _ringGap = AppSpace.lg;

String _instruction(AppLocalizations l10n, LivenessStep step) => switch (step) {
  LivenessStep.lookAtCamera => l10n.livenessLook,
  LivenessStep.turnHead => l10n.livenessTurn,
  LivenessStep.blink => l10n.livenessBlink,
};

class _LivenessRing extends StatelessWidget {
  const _LivenessRing({
    required this.pulse,
    required this.progress,
    required this.captured,
  });

  final Animation<double> pulse;
  final double progress;
  final bool captured;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: progress),
        duration: AppMotion.of(context, AppMotion.slow),
        curve: AppMotion.curve,
        builder: (context, value, badge) => CustomPaint(
          painter: _OvalRingPainter(
            progress: value,
            pulse: pulse,
            pulsing: !captured,
            color: captured ? AppColors.success : AppColors.teal300,
          ),
          child: badge,
        ),
        child: Center(
          child: AnimatedScale(
            scale: captured ? 1 : 0,
            duration: AppMotion.of(context, AppMotion.medium),
            curve: AppMotion.pop,
            child: Container(
              width: AppSpace.xxxl + AppSpace.lg,
              height: AppSpace.xxxl + AppSpace.lg,
              decoration: const BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
                boxShadow: AppShadows.lg,
              ),
              child: const Icon(
                Icons.check_rounded,
                size: AppSpace.xxl,
                color: AppColors.onPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OvalRingPainter extends CustomPainter {
  _OvalRingPainter({
    required this.progress,
    required this.pulse,
    required this.pulsing,
    required this.color,
  }) : super(repaint: pulse);

  final double progress;
  final Animation<double> pulse;
  final bool pulsing;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final oval = (Offset.zero & size).deflate(_ringGap);
    final line = Paint()..style = PaintingStyle.stroke;

    if (pulsing) {
      final p = pulse.value;
      canvas.drawOval(
        oval.inflate(_ringGap * p),
        line
          ..strokeWidth = 2
          ..color = AppColors.teal200.withValues(alpha: 0.6 * (1 - p)),
      );
    }

    canvas.drawOval(
      oval,
      line
        ..strokeWidth = 2
        ..color = AppColors.onPrimary.withValues(alpha: 0.75),
    );

    final track = oval.inflate(_ringGap / 2);
    canvas.drawOval(
      track,
      line
        ..strokeWidth = 6
        ..color = AppColors.onPrimary.withValues(alpha: 0.15),
    );
    if (progress <= 0) return;
    canvas.drawArc(
      track,
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      line
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_OvalRingPainter old) =>
      old.progress != progress ||
      old.pulsing != pulsing ||
      old.color != color ||
      old.pulse != pulse;
}

enum _ChipState { done, active, pending }

class _StepChip extends StatelessWidget {
  const _StepChip({required this.label, required this.state});

  final String label;
  final _ChipState state;

  @override
  Widget build(BuildContext context) {
    final (border, fill, icon) = switch (state) {
      _ChipState.done => (
        AppColors.success,
        AppColors.success.withValues(alpha: 0.18),
        Icons.check_circle_rounded,
      ),
      _ChipState.active => (
        AppColors.sand400,
        AppColors.sand400.withValues(alpha: 0.18),
        Icons.radio_button_checked_rounded,
      ),
      _ChipState.pending => (
        AppColors.teal400,
        AppColors.teal900.withValues(alpha: 0),
        Icons.radio_button_unchecked_rounded,
      ),
    };
    return Semantics(
      checked: state == _ChipState.done,
      child: AnimatedContainer(
        duration: AppMotion.of(context, AppMotion.medium),
        curve: AppMotion.curve,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md,
          vertical: AppSpace.xs + 2,
        ),
        decoration: BoxDecoration(
          color: fill,
          border: Border.all(color: border, width: 1.5),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: border),
            const SizedBox(width: AppSpace.xs + 2),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: state == _ChipState.pending
                    ? AppColors.teal200
                    : AppColors.onPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
