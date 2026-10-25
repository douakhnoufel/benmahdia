import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/flow_top_bar.dart';
import '../../widgets/staggered_reveal.dart';
import 'booking_format.dart';
import 'booking_models.dart';
import 'booking_repository.dart';
import 'booking_widgets.dart';

/// Booking step 1: pick a doctor. Each card shows the next free time. The
/// first doctor a patient books becomes their primary doctor (PRD 4.3).
class BookDoctorScreen extends ConsumerStatefulWidget {
  const BookDoctorScreen({super.key, required this.onNext});

  final ValueChanged<Doctor> onNext;

  @override
  ConsumerState<BookDoctorScreen> createState() => _BookDoctorScreenState();
}

class _BookDoctorScreenState extends ConsumerState<BookDoctorScreen> {
  late Future<List<Doctor>> _doctors = _load();
  String? _pickedId;

  Future<List<Doctor>> _load() => ref.read(bookingRepositoryProvider).doctors();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: FutureBuilder<List<Doctor>>(
          future: _doctors,
          builder: (context, snapshot) {
            final doctors = snapshot.data ?? const <Doctor>[];
            final pickedId =
                _pickedId ?? (doctors.length == 1 ? doctors.first.id : null);
            final picked = doctors.where((d) => d.id == pickedId).firstOrNull;

            final Widget body;
            if (snapshot.hasError) {
              body = LoadError(
                onRetry: () => setState(() {
                  _doctors = _load();
                }),
              );
            } else if (!snapshot.hasData) {
              body = const Center(child: CircularProgressIndicator());
            } else {
              body = ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.screenHorizontal,
                  AppSpace.xl,
                  AppSpace.screenHorizontal,
                  AppSpace.xl,
                ),
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      l10n.bookDoctorTitle,
                      style: text.headlineLarge,
                    ),
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text(l10n.bookDoctorBody, style: text.bodyLarge),
                  const SizedBox(height: AppSpace.xl),
                  StaggeredReveal(
                    children: [
                      for (final d in doctors)
                        _DoctorCard(
                          doctor: d,
                          selected: d.id == pickedId,
                          onTap: () => setState(() => _pickedId = d.id),
                        ),
                    ],
                  ),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FlowTopBar(title: l10n.bookTitle, step: 1, total: 3),
                Expanded(child: body),
                BottomBar(
                  children: [
                    InfoLine(
                      text: l10n.bookNotice(
                        ref.read(bookingRepositoryProvider).notice.inHours,
                      ),
                      icon: Icons.schedule_rounded,
                      center: true,
                    ),
                    FilledButton(
                      onPressed: picked == null
                          ? null
                          : () => widget.onNext(picked),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(child: Text(l10n.bookChooseTime)),
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

class _DoctorCard extends ConsumerStatefulWidget {
  const _DoctorCard({
    required this.doctor,
    required this.selected,
    required this.onTap,
  });

  final Doctor doctor;
  final bool selected;
  final VoidCallback onTap;

  @override
  ConsumerState<_DoctorCard> createState() => _DoctorCardState();
}

class _DoctorCardState extends ConsumerState<_DoctorCard> {
  late final Future<List<DaySlots>> _days = ref
      .read(bookingRepositoryProvider)
      .calendar(widget.doctor);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final lang = Localizations.localeOf(context).languageCode;
    final medium = AppMotion.of(context, AppMotion.medium);
    final d = widget.doctor;
    final selected = widget.selected;

    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: medium,
          curve: AppMotion.curve,
          padding: const EdgeInsets.all(AppSpace.lg),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: selected ? AppColors.teal500 : AppColors.border,
              width: selected ? 2 : 1,
            ),
            boxShadow: selected ? AppShadows.lg : AppShadows.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpace.md,
            children: [
              Row(
                children: [
                  DoctorAvatar(initials: d.initials(lang)),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.name(lang), style: text.titleLarge),
                        Text(
                          '${l10n.bookClinic} · '
                          '${l10n.bookMinutes(d.slotMinutes)} · '
                          '${l10n.bookPrice(d.priceDzd)}',
                          style: text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  AnimatedSwitcher(
                    duration: medium,
                    transitionBuilder: (child, animation) =>
                        ScaleTransition(scale: animation, child: child),
                    child: selected
                        ? const _Mark(key: ValueKey(true), on: true)
                        : const _Mark(key: ValueKey(false), on: false),
                  ),
                ],
              ),
              FutureBuilder<List<DaySlots>>(
                future: _days,
                builder: (context, snapshot) {
                  final next = snapshot.data
                      ?.expand((day) => day.slots)
                      .where((s) => s.free)
                      .firstOrNull;
                  final loaded = snapshot.hasData;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.md,
                      vertical: AppSpace.sm,
                    ),
                    decoration: BoxDecoration(
                      color: next != null || !loaded
                          ? AppColors.teal50
                          : AppColors.sand100,
                      borderRadius: BorderRadius.circular(AppRadius.field),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: AppSpace.sm,
                          height: AppSpace.sm,
                          decoration: BoxDecoration(
                            color: next != null
                                ? AppColors.success
                                : AppColors.sand400,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: AppSpace.sm),
                        Expanded(
                          child: Text(
                            !loaded
                                ? ''
                                : next == null
                                ? l10n.bookNoFree(
                                    ref
                                        .read(bookingRepositoryProvider)
                                        .horizon
                                        .inDays,
                                  )
                                : l10n.bookNextFree(
                                    '${l10n.longDate(next.start)} · '
                                    '${hhmm(next.start)}',
                                  ),
                            style: text.bodySmall?.copyWith(
                              color: AppColors.textStrong,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Mark extends StatelessWidget {
  const _Mark({super.key, required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    if (!on) {
      return Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.border, width: 2),
        ),
      );
    }
    return Container(
      width: 26,
      height: 26,
      decoration: const BoxDecoration(
        color: AppColors.teal500,
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.check_rounded,
        size: 16,
        color: AppColors.onPrimary,
      ),
    );
  }
}
