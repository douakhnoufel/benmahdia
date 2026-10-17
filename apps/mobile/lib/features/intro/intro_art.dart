import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/app_mark.dart';
import '../../widgets/sobriety_ring.dart';
import '../../widgets/staggered_reveal.dart';

// Pictures for the intro slides: small, animated previews of real app
// screens, built from the same widgets. They hold sample data only and are
// decorative; the slide title and body carry the meaning for screen readers.

/// Slide 1: the day ring fills to 42 of 60 and the week's check marks pop in.
class StreakArt extends StatelessWidget {
  const StreakArt({super.key, required this.active});

  final bool active;

  static const _days = 42;
  static const _goal = 60;
  static const _weekDone = 6;
  static const _weekTotal = 7;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _Scene(
      child: _FloatCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Pill(dot: AppColors.sand400, label: l10n.ringNextGoal(_goal)),
            const SizedBox(height: AppSpace.md),
            SobrietyRing(
              days: _days,
              goal: _goal,
              label: l10n.ringDaysLabel(_days),
              semanticLabel: l10n.ringOfGoal(_days, _goal),
            ),
            const SizedBox(height: AppSpace.md),
            StaggeredReveal(
              active: active,
              pop: true,
              direction: Axis.horizontal,
              crossAxisAlignment: CrossAxisAlignment.center,
              spacing: AppSpace.xs + 2,
              children: [
                for (var i = 0; i < _weekTotal; i++)
                  _DayDot(done: i < _weekDone),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              l10n.introWeek(_weekDone, _weekTotal),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Slide 2: a late-night message and the companion's calm reply arrive one
/// after the other, then the quick actions.
class CompanionArt extends StatelessWidget {
  const CompanionArt({super.key, required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return _Scene(
      child: _FloatCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const AppMark(size: 32),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.companionName, style: text.titleLarge),
                      Row(
                        children: [
                          Container(
                            width: AppSpace.sm,
                            height: AppSpace.sm,
                            decoration: const BoxDecoration(
                              color: AppColors.success,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: AppSpace.xs + 2),
                          Flexible(
                            child: Text(
                              l10n.companionOnline,
                              style: text.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            const Divider(),
            const SizedBox(height: AppSpace.md),
            StaggeredReveal(
              active: active,
              spacing: AppSpace.sm,
              children: [
                _Bubble(text: l10n.chatSample, outgoing: true),
                _Bubble(text: l10n.chatReplySample, outgoing: false),
                Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.sm,
                  children: [
                    _OutlinePill(
                      label: l10n.chipBreathing,
                      color: AppColors.teal700,
                    ),
                    _OutlinePill(
                      label: l10n.chipEmergency,
                      color: AppColors.danger,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Slide 3: the next appointment, today's medicines and the weekly summary
/// slide in one by one.
class DoctorArt extends StatelessWidget {
  const DoctorArt({super.key, required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return _Scene(
      child: StaggeredReveal(
        active: active,
        children: [
          _FloatCard(
            child: Row(
              children: [
                const _IconTile(icon: Icons.calendar_month_rounded),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.apptNext, style: text.bodySmall),
                      Text(l10n.apptDoctorSample, style: text.titleLarge),
                      Text(l10n.apptWhenSample, style: text.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                _StatusPill(
                  label: l10n.apptConfirmed,
                  color: AppColors.success,
                ),
              ],
            ),
          ),
          _FloatCard(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
            child: Column(
              children: [
                _MedRow(
                  name: l10n.medMorning,
                  time: '08:00',
                  status: l10n.medTaken,
                  taken: true,
                ),
                const Divider(),
                _MedRow(
                  name: l10n.medEvening,
                  time: '20:00',
                  status: l10n.medLater,
                  taken: false,
                ),
              ],
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: _Pill(
              icon: Icons.insights_rounded,
              label: l10n.doctorWeeklySummary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Soft dawn backdrop shared by the three pictures. Scales its content down
/// on short screens; the picture is decorative, so semantics are excluded.
class _Scene extends StatelessWidget {
  const _Scene({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sheet),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.teal50, AppColors.sand100],
            ),
          ),
          child: Stack(
            children: [
              const Positioned.fill(
                child: CustomPaint(painter: _HillsPainter()),
              ),
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.lg),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SizedBox(width: 300, child: child),
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

class _HillsPainter extends CustomPainter {
  const _HillsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final sun = Offset(w * 0.5, h * 1.02);
    canvas.drawCircle(
      sun,
      h * 0.45,
      Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.sand300.withValues(alpha: 0.9),
            AppColors.sand300.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: sun, radius: h * 0.45)),
    );
    final back = Path()
      ..moveTo(0, h * 0.8)
      ..quadraticBezierTo(w * 0.3, h * 0.7, w * 0.55, h * 0.78)
      ..quadraticBezierTo(w * 0.8, h * 0.86, w, h * 0.76)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(back, Paint()..color = AppColors.teal100);
    final front = Path()
      ..moveTo(0, h * 0.9)
      ..quadraticBezierTo(w * 0.45, h * 0.82, w, h * 0.92)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(front, Paint()..color = AppColors.teal200);
  }

  @override
  bool shouldRepaint(_HillsPainter old) => false;
}

class _FloatCard extends StatelessWidget {
  const _FloatCard({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpace.lg),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadows.lg,
      ),
      child: child,
    );
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({required this.done});

  final bool done;

  @override
  Widget build(BuildContext context) {
    const size = AppSpace.xl;
    if (!done) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.sand400, width: 2),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: AppColors.teal500,
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.check_rounded,
        size: AppSpace.lg,
        color: AppColors.onPrimary,
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.outgoing});

  final String text;
  final bool outgoing;

  @override
  Widget build(BuildContext context) {
    const big = Radius.circular(AppRadius.card);
    const tail = Radius.circular(AppSpace.xs);
    final style = Theme.of(context).textTheme.bodyMedium;
    return Align(
      alignment: outgoing
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md,
            vertical: AppSpace.sm,
          ),
          decoration: BoxDecoration(
            color: outgoing ? AppColors.teal500 : AppColors.surface,
            border: outgoing ? null : Border.all(color: AppColors.border),
            borderRadius: BorderRadiusDirectional.only(
              topStart: big,
              topEnd: big,
              bottomStart: outgoing ? big : tail,
              bottomEnd: outgoing ? tail : big,
            ),
          ),
          child: Text(
            text,
            style: style?.copyWith(
              color: outgoing ? AppColors.onPrimary : AppColors.textStrong,
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, this.dot, this.icon});

  final String label;
  final Color? dot;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: AppSpace.xs + 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot != null)
            Container(
              width: AppSpace.sm,
              height: AppSpace.sm,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
          if (icon != null)
            Icon(icon, size: AppSpace.lg, color: AppColors.teal600),
          const SizedBox(width: AppSpace.sm),
          Flexible(
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: AppColors.textStrong),
            ),
          ),
        ],
      ),
    );
  }
}

class _OutlinePill extends StatelessWidget {
  const _OutlinePill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: AppSpace.xs + 2,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.sm + 2,
        vertical: AppSpace.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.tint(color),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppColors.textStrong,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.teal50,
        borderRadius: BorderRadius.circular(AppRadius.field),
      ),
      child: Icon(icon, color: AppColors.teal600),
    );
  }
}

class _MedRow extends StatelessWidget {
  const _MedRow({
    required this.name,
    required this.time,
    required this.status,
    required this.taken,
  });

  final String name;
  final String time;
  final String status;
  final bool taken;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          const Icon(Icons.medication_rounded, color: AppColors.teal600),
          const SizedBox(width: AppSpace.md),
          Expanded(child: Text(name, style: text.bodyMedium)),
          Text(
            time,
            style: text.bodySmall?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          _StatusPill(
            label: status,
            color: taken ? AppColors.success : AppColors.warning,
          ),
        ],
      ),
    );
  }
}
