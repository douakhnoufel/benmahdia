import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/flow_top_bar.dart';
import 'booking_format.dart';
import 'booking_models.dart';
import 'booking_repository.dart';
import 'booking_widgets.dart';

/// Booking step 2: a scrollable strip of the next 60 days and the chosen
/// day's slots, grouped into morning and afternoon. Taken or too-soon times
/// are greyed out; the patient never sees who booked them. When a follow-up
/// is due, the strip opens on the suggested day (30 days after the latest
/// visit) and the patient can still pick a day before or after it.
/// Continue holds the slot.
class BookSlotScreen extends ConsumerStatefulWidget {
  const BookSlotScreen({super.key, required this.doctor, required this.onNext});

  final Doctor doctor;
  final ValueChanged<Hold> onNext;

  @override
  ConsumerState<BookSlotScreen> createState() => _BookSlotScreenState();
}

typedef _Agenda = ({List<DaySlots> days, FollowUp? followUp});

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Where the suggested follow-up day sits in [days], if it is bookable.
int? _followUpIndex(List<DaySlots> days, FollowUp? followUp) {
  if (followUp == null) return null;
  final i = days.indexWhere((d) => _sameDay(d.day, followUp.day));
  return i < 0 ? null : i;
}

/// The day with free slots nearest to [target]; the earlier one on a tie.
int? _nearestFree(List<DaySlots> days, int target) {
  for (var off = 0; off < days.length; off++) {
    for (final i in [target - off, target + off]) {
      if (i >= 0 && i < days.length && days[i].hasFree) return i;
    }
  }
  return null;
}

class _BookSlotScreenState extends ConsumerState<BookSlotScreen> {
  late Future<_Agenda> _agenda = _load();
  int? _dayIndex;
  DateTime? _slot;
  bool _holding = false;

  Future<_Agenda> _load() async {
    final repo = ref.read(bookingRepositoryProvider);
    final (days, followUp) = await (
      repo.calendar(widget.doctor),
      repo.followUp(),
    ).wait;
    return (days: days, followUp: followUp);
  }

  /// The day the strip opens on: the free day nearest the follow-up, or the
  /// first free day.
  int _openingDay(_Agenda agenda) {
    final target = _followUpIndex(agenda.days, agenda.followUp);
    final suggested = target == null ? null : _nearestFree(agenda.days, target);
    if (suggested != null) return suggested;
    final firstFree = agenda.days.indexWhere((d) => d.hasFree);
    return firstFree < 0 ? 0 : firstFree;
  }

  void _pickDay(int index) => setState(() {
    _dayIndex = index;
    _slot = null;
  });

  Future<void> _continue() async {
    final slot = _slot;
    if (slot == null) return;
    final repo = ref.read(bookingRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    setState(() => _holding = true);
    try {
      final hold = await repo.hold(widget.doctor, slot);
      if (!mounted) return;
      widget.onNext(hold);
    } on SlotUnavailable {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.bookSlotGone)));
      setState(() {
        _slot = null;
        _agenda = _load();
      });
    } finally {
      if (mounted) setState(() => _holding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final lang = Localizations.localeOf(context).languageCode;
    final now = ref.read(bookingRepositoryProvider).now();
    final d = widget.doctor;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: FutureBuilder<_Agenda>(
          future: _agenda,
          builder: (context, snapshot) {
            final agenda = snapshot.data;
            final Widget body;
            DaySlots? day;
            if (snapshot.hasError) {
              body = LoadError(
                onRetry: () => setState(() {
                  _agenda = _load();
                }),
              );
            } else if (agenda == null) {
              body = const Center(child: CircularProgressIndicator());
            } else {
              final days = agenda.days;
              final opening = _openingDay(agenda);
              final index = _dayIndex ?? opening;
              final followUp = agenda.followUp;
              final followUpIndex = _followUpIndex(days, followUp);
              final overdue = followUp?.overdueOn(now) ?? false;
              day = days[index];
              const side = EdgeInsets.symmetric(
                horizontal: AppSpace.screenHorizontal,
              );
              body = ListView(
                padding: const EdgeInsets.only(
                  top: AppSpace.lg,
                  bottom: AppSpace.xl,
                ),
                children: [
                  Padding(
                    padding: side,
                    child: _DoctorStrip(doctor: d, lang: lang),
                  ),
                  if (followUp != null &&
                      (followUpIndex != null || overdue)) ...[
                    const SizedBox(height: AppSpace.md),
                    Padding(
                      padding: side,
                      child: _FollowUpBanner(
                        followUp: followUp,
                        overdue: overdue,
                        onShow: followUpIndex != null && index != opening
                            ? () => _pickDay(opening)
                            : null,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpace.xl),
                  Padding(
                    padding: side,
                    child: AnimatedSwitcher(
                      duration: AppMotion.of(context, AppMotion.fast),
                      layoutBuilder: (current, previous) => Stack(
                        alignment: AlignmentDirectional.centerStart,
                        children: [...previous, ?current],
                      ),
                      child: Text(
                        '${l10n.month(day.day)} ${day.day.year}',
                        key: ValueKey(day.day.month),
                        style: text.titleLarge,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpace.xs),
                  _DayStrip(
                    days: days,
                    selected: index,
                    followUp: followUpIndex,
                    onPick: _pickDay,
                  ),
                  const SizedBox(height: AppSpace.xl),
                  Padding(
                    padding: side,
                    child: AnimatedSwitcher(
                      duration: AppMotion.of(context, AppMotion.medium),
                      child: KeyedSubtree(
                        key: ValueKey(index),
                        child: day.open
                            ? _DaySlotsView(
                                day: day,
                                selected: _slot,
                                onPick: (s) => setState(() => _slot = s),
                              )
                            : _NoSlots(closure: day.closure),
                      ),
                    ),
                  ),
                ],
              );
            }

            final slot = _slot;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FlowTopBar(title: l10n.bookSlotTitle, step: 2, total: 3),
                Expanded(child: body),
                BottomBar(
                  children: [
                    AnimatedSwitcher(
                      duration: AppMotion.of(context, AppMotion.fast),
                      child: slot == null
                          ? Text(
                              l10n.bookPickTime,
                              key: const ValueKey('hint'),
                              textAlign: TextAlign.center,
                              style: text.bodyMedium?.copyWith(
                                color: AppColors.textMuted,
                              ),
                            )
                          : Row(
                              key: ValueKey(slot),
                              children: [
                                const Icon(
                                  Icons.event_rounded,
                                  size: 20,
                                  color: AppColors.teal600,
                                ),
                                const SizedBox(width: AppSpace.sm),
                                Expanded(
                                  child: Text(
                                    '${l10n.longDate(slot)} · ${hhmm(slot)}',
                                    style: text.titleLarge?.copyWith(
                                      fontSize: AppType.body.size,
                                    ),
                                  ),
                                ),
                                Text(
                                  l10n.bookMinutes(d.slotMinutes),
                                  style: text.bodySmall,
                                ),
                              ],
                            ),
                    ),
                    FilledButton(
                      onPressed: slot == null || _holding || day == null
                          ? null
                          : _continue,
                      child: _holding
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.onPrimary,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(l10n.bookContinue),
                                const SizedBox(width: AppSpace.sm),
                                const Icon(Icons.arrow_forward, size: 20),
                              ],
                            ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Why the strip opened on this day: 30 days after the latest visit, or the
/// follow-up is already due. [onShow] jumps back to the suggested day.
class _FollowUpBanner extends StatelessWidget {
  const _FollowUpBanner({
    required this.followUp,
    required this.overdue,
    required this.onShow,
  });

  final FollowUp followUp;
  final bool overdue;
  final VoidCallback? onShow;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final span = l10n.bookDays(followUp.days);
    final since = l10n.longDate(followUp.after.start);
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpace.md + 2,
        AppSpace.md,
        AppSpace.md + 2,
        AppSpace.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.teal50,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FollowUpMark(),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  overdue
                      ? l10n.bookFollowUpOverdueTitle
                      : l10n.bookFollowUpTitle(l10n.longDate(followUp.day)),
                  style: text.titleLarge?.copyWith(fontSize: AppType.body.size),
                ),
                const SizedBox(height: 2),
                Text(
                  overdue
                      ? l10n.bookFollowUpOverdueBody(span, since)
                      : l10n.bookFollowUpBody(span, since),
                  style: text.bodySmall?.copyWith(color: AppColors.textBody),
                ),
                if (onShow case final show?)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpace.xs),
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpace.sm,
                        ),
                        minimumSize: const Size(0, 44),
                      ),
                      onPressed: show,
                      icon: const Icon(Icons.flag_rounded, size: 18),
                      label: Text(l10n.bookFollowUpShow),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The horizontally scrolling days. It opens with [selected] in view and
/// scrolls a newly selected day into view when it is off screen.
class _DayStrip extends StatefulWidget {
  const _DayStrip({
    required this.days,
    required this.selected,
    required this.followUp,
    required this.onPick,
  });

  final List<DaySlots> days;
  final int selected;

  /// Index of the suggested follow-up day, if it is in [days].
  final int? followUp;
  final ValueChanged<int> onPick;

  @override
  State<_DayStrip> createState() => _DayStripState();
}

class _DayStripState extends State<_DayStrip> {
  /// Width of one day, pill plus gap.
  static const _extent = 54.0;
  static const _gap = 3.0;
  static const _edge = AppSpace.screenHorizontal - _gap;

  ScrollController? _controller;
  double _viewport = 0;

  /// Offset that centres day [i], kept inside the scroll range.
  double _centred(int i) {
    final content = widget.days.length * _extent + 2 * _edge;
    final centre = _edge + i * _extent + _extent / 2 - _viewport / 2;
    return centre.clamp(0.0, math.max(0.0, content - _viewport));
  }

  @override
  void didUpdateWidget(_DayStrip old) {
    super.didUpdateWidget(old);
    final c = _controller;
    if (c == null || !c.hasClients || old.selected == widget.selected) return;
    final start = _edge + widget.selected * _extent;
    final inView = start >= c.offset && start + _extent <= c.offset + _viewport;
    if (inView) return;
    final to = _centred(widget.selected);
    final duration = AppMotion.of(context, AppMotion.medium);
    if (duration == Duration.zero) {
      c.jumpTo(to);
    } else {
      unawaited(c.animateTo(to, duration: duration, curve: AppMotion.curve));
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewport = constraints.maxWidth;
        final controller = _controller ??= ScrollController(
          initialScrollOffset: _centred(widget.selected),
        );
        return SingleChildScrollView(
          controller: controller,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: _edge),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < widget.days.length; i++)
                SizedBox(
                  width: _extent,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: _gap),
                    child: _DayPill(
                      day: widget.days[i],
                      today: i == 0,
                      selected: i == widget.selected,
                      followUp: i == widget.followUp,
                      onTap: () => widget.onPick(i),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _DoctorStrip extends StatelessWidget {
  const _DoctorStrip({required this.doctor, required this.lang});

  final Doctor doctor;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md + 2,
        vertical: AppSpace.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          DoctorAvatar(initials: doctor.initials(lang), size: 40),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doctor.name(lang),
                  style: text.titleLarge?.copyWith(fontSize: AppType.body.size),
                ),
                Text(
                  '${l10n.bookMinutes(doctor.slotMinutes)} · '
                  '${l10n.bookPrice(doctor.priceDzd)}',
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: Text(l10n.bookChange),
          ),
        ],
      ),
    );
  }
}

class _DayPill extends StatelessWidget {
  const _DayPill({
    required this.day,
    required this.today,
    required this.selected,
    required this.followUp,
    required this.onTap,
  });

  final DaySlots day;
  final bool today;
  final bool selected;

  /// Whether this is the suggested follow-up day; it carries a flag.
  final bool followUp;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final open = day.open;
    final (fill, fg, border, width) = selected
        ? (AppColors.teal500, AppColors.onPrimary, AppColors.teal500, 1.0)
        : today
        ? (AppColors.surface, AppColors.teal700, AppColors.teal500, 2.0)
        : open
        ? (AppColors.surface, AppColors.textStrong, AppColors.border, 1.0)
        : (AppColors.sand100, AppColors.textMuted, AppColors.sand100, 1.0);
    final dot = !day.hasFree
        ? Colors.transparent
        : selected
        ? AppColors.onPrimary
        : AppColors.success;

    final label = l10n.longDate(day.day);
    return Semantics(
      button: true,
      selected: selected,
      label: followUp ? l10n.bookFollowUpDay(label) : label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          fit: StackFit.passthrough,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: _badgeRoom),
              child: AnimatedContainer(
                duration: AppMotion.of(context, AppMotion.medium),
                curve: AppMotion.curve,
                padding: const EdgeInsets.only(top: AppSpace.sm, bottom: 6),
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(AppRadius.button),
                  border: Border.all(color: border, width: width),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.shortWeekday(day.day),
                      maxLines: 1,
                      softWrap: false,
                      style: text.bodySmall?.copyWith(color: fg, fontSize: 12),
                    ),
                    Text(
                      '${day.day.day}',
                      style: text.titleLarge?.copyWith(color: fg),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: dot,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (followUp)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: FollowUpMark(small: true),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Space above each day pill for the follow-up flag.
const _badgeRoom = AppSpace.md;

class _DaySlotsView extends StatelessWidget {
  const _DaySlotsView({
    required this.day,
    required this.selected,
    required this.onPick,
  });

  final DaySlots day;
  final DateTime? selected;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final morning = day.slots.where((s) => s.start.hour < 12).toList();
    final afternoon = day.slots.where((s) => s.start.hour >= 12).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (morning.isNotEmpty) ...[
          SectionLabel(icon: Icons.wb_sunny_outlined, text: l10n.bookMorning),
          const SizedBox(height: AppSpace.sm),
          _SlotGrid(slots: morning, selected: selected, onPick: onPick),
          const SizedBox(height: AppSpace.lg),
        ],
        if (afternoon.isNotEmpty) ...[
          SectionLabel(
            icon: Icons.wb_twilight_rounded,
            text: l10n.bookAfternoon,
          ),
          const SizedBox(height: AppSpace.sm),
          _SlotGrid(slots: afternoon, selected: selected, onPick: onPick),
          const SizedBox(height: AppSpace.lg),
        ],
        Wrap(
          spacing: AppSpace.md,
          runSpacing: AppSpace.xs,
          children: [
            _Legend(color: AppColors.surface, label: l10n.bookLegendFree),
            _Legend(color: AppColors.sand100, label: l10n.bookLegendTaken),
            _Legend(color: AppColors.teal500, label: l10n.bookLegendYours),
          ],
        ),
      ],
    );
  }
}

class _SlotGrid extends StatelessWidget {
  const _SlotGrid({
    required this.slots,
    required this.selected,
    required this.onPick,
  });

  final List<Slot> slots;
  final DateTime? selected;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    return GridView(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: AppSpace.sm,
        crossAxisSpacing: AppSpace.sm,
        mainAxisExtent: 44,
      ),
      children: [
        for (final s in slots)
          _SlotPill(
            slot: s,
            selected: s.start == selected,
            onTap: () => onPick(s.start),
          ),
      ],
    );
  }
}

class _SlotPill extends StatelessWidget {
  const _SlotPill({
    required this.slot,
    required this.selected,
    required this.onTap,
  });

  final Slot slot;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final free = slot.free;
    final (fill, fg, border) = selected
        ? (AppColors.teal500, AppColors.onPrimary, AppColors.teal500)
        : free
        ? (AppColors.surface, AppColors.textStrong, AppColors.border)
        : (AppColors.sand100, AppColors.textMuted, AppColors.sand100);

    return Semantics(
      button: true,
      enabled: free,
      selected: selected,
      label: hhmm(slot.start),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: free ? onTap : null,
        child: AnimatedContainer(
          duration: AppMotion.of(context, AppMotion.fast),
          curve: AppMotion.curve,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(AppRadius.field),
            border: Border.all(color: border),
            boxShadow: selected ? AppShadows.card : null,
          ),
          child: LtrText(
            hhmm(slot.start),
            style: text.bodyMedium?.copyWith(
              color: fg,
              fontWeight: FontWeight.w500,
              decoration: free ? null : TextDecoration.lineThrough,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(AppSpace.xs),
            border: Border.all(color: AppColors.border),
          ),
        ),
        const SizedBox(width: AppSpace.xs),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _NoSlots extends StatelessWidget {
  const _NoSlots({required this.closure});

  final DayClosure closure;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.xl,
        vertical: AppSpace.xxl,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.sand300),
      ),
      child: Column(
        children: [
          Container(
            width: AppSpace.xxxl,
            height: AppSpace.xxxl,
            decoration: const BoxDecoration(
              color: AppColors.sand100,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.event_busy_rounded,
              color: AppColors.sand500,
            ),
          ),
          const SizedBox(height: AppSpace.md),
          Text(l10n.bookNoSlots, style: text.titleLarge),
          const SizedBox(height: AppSpace.xs),
          Text(
            closure == DayClosure.tooSoon ? l10n.bookTooSoon : l10n.bookClosed,
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
