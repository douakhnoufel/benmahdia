import 'dart:async';
import 'dart:math' as math;

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
import 'payment_launcher.dart';

/// Booking step 3: the held slot with a live countdown, the summary and the
/// payment choice (Edahabia or CIB through Chargily, or at the clinic during
/// the pilot). When time runs out the slot is released (PRD 4.3).
class BookConfirmScreen extends ConsumerStatefulWidget {
  const BookConfirmScreen({
    super.key,
    required this.hold,
    required this.onDone,
    required this.onExpired,
  });

  final Hold hold;
  final ValueChanged<Appointment> onDone;

  /// Goes back to pick another time after the hold expired.
  final VoidCallback onExpired;

  @override
  ConsumerState<BookConfirmScreen> createState() => _BookConfirmScreenState();
}

class _BookConfirmScreenState extends ConsumerState<BookConfirmScreen> {
  static const _tick = Duration(seconds: 1);
  static const _pollEvery = Duration(seconds: 3);

  late final BookingRepository _repo = ref.read(bookingRepositoryProvider);
  late final Duration _total = _repo.holdFor;
  late Duration _left = widget.hold.expiresAt.difference(_repo.now());
  Timer? _timer;
  late PaymentMethod _method = _repo.methods.contains(PaymentMethod.edahabia)
      ? PaymentMethod.edahabia
      : _repo.methods.first;
  bool _paying = false;
  bool _booked = false;

  /// A Chargily checkout is open: from now on only the server decides
  /// whether the slot is booked or given back.
  bool _checkoutOpen = false;
  Timer? _poll;

  bool get _expired => _left <= Duration.zero;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_tick, (_) => _onTick());
  }

  void _onTick() {
    setState(() => _left -= _tick);
    if (_expired) {
      _timer?.cancel();
      if (!_checkoutOpen) unawaited(_repo.release(widget.hold));
    }
  }

  Future<void> _confirm() async {
    setState(() => _paying = true);
    if (_method.online && _repo.cardsUseCheckout) {
      await _payByCard();
      return;
    }
    try {
      final appointment = await _repo.confirm(widget.hold, _method);
      if (!mounted) return;
      _booked = true;
      _timer?.cancel();
      widget.onDone(appointment);
    } on SlotUnavailable {
      // The server gave the slot back (the hold ran out): show the same
      // "time is up" view as the timer does.
      if (!mounted) return;
      _timer?.cancel();
      setState(() => _left = Duration.zero);
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  /// Opens Chargily's checkout, then waits for the server to confirm the
  /// payment from Chargily's webhook (PRD 4.4); the app never confirms a
  /// card payment on its own.
  Future<void> _payByCard() async {
    final open = ref.read(openUrlProvider);
    try {
      final url = await _repo.checkout(widget.hold, _method);
      _checkoutOpen = true;
      await open(url);
      if (!mounted) return;
      _poll = Timer.periodic(_pollEvery, (_) => unawaited(_checkPaid()));
    } on SlotUnavailable {
      _showExpired();
    } on BookingUnavailable {
      if (mounted) setState(() => _paying = false);
    }
  }

  Future<void> _checkPaid() async {
    try {
      final appointment = await _repo.paid(widget.hold);
      if (appointment == null || !mounted || _booked) return;
      _booked = true;
      _poll?.cancel();
      _timer?.cancel();
      widget.onDone(appointment);
    } on SlotUnavailable {
      _showExpired();
    } on BookingUnavailable {
      // Offline for a moment: the next check tries again.
    }
  }

  void _showExpired() {
    _poll?.cancel();
    _timer?.cancel();
    if (mounted) {
      setState(() {
        _paying = false;
        _left = Duration.zero;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _poll?.cancel();
    // Leaving without booking gives the slot back, unless a payment may be
    // under way at Chargily: then the server decides.
    if (!_booked && !_expired && !_checkoutOpen) {
      unawaited(_repo.release(widget.hold));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final price = widget.hold.doctor.priceDzd;
    final online = _method.online;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FlowTopBar(title: l10n.bookConfirmTitle, step: 3, total: 3),
            Expanded(
              child: AnimatedSwitcher(
                duration: AppMotion.of(context, AppMotion.medium),
                child: _expired
                    ? _Expired(
                        key: const ValueKey('expired'),
                        onPickAnother: widget.onExpired,
                      )
                    : ListView(
                        key: const ValueKey('form'),
                        padding: const EdgeInsets.fromLTRB(
                          AppSpace.screenHorizontal,
                          AppSpace.lg,
                          AppSpace.screenHorizontal,
                          AppSpace.xl,
                        ),
                        children: [
                          _HoldBanner(left: _left, total: _total),
                          const SizedBox(height: AppSpace.lg),
                          _Summary(hold: widget.hold),
                          const SizedBox(height: AppSpace.xl),
                          Text(
                            l10n.bookPayMethod,
                            style: text.labelMedium?.copyWith(
                              color: AppColors.textBody,
                            ),
                          ),
                          const SizedBox(height: AppSpace.sm),
                          StaggeredReveal(
                            spacing: AppSpace.sm,
                            children: [
                              for (final m in PaymentMethod.values)
                                if (_repo.methods.contains(m))
                                _MethodCard(
                                  method: m,
                                  selected: m == _method,
                                  onTap: () => setState(() => _method = m),
                                ),
                            ],
                          ),
                          const SizedBox(height: AppSpace.lg),
                          InfoLine(text: l10n.bookCancelRule),
                        ],
                      ),
              ),
            ),
            if (!_expired)
              BottomBar(
                children: [
                  FilledButton(
                    onPressed: _paying ? null : _confirm,
                    child: _paying
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
                              if (online) ...[
                                const Icon(
                                  Icons.lock_outline_rounded,
                                  size: 18,
                                ),
                                const SizedBox(width: AppSpace.sm),
                              ],
                              Flexible(
                                child: Text(
                                  online
                                      ? l10n.bookPay(price)
                                      : l10n.bookConfirmClinic,
                                ),
                              ),
                            ],
                          ),
                  ),
                  Text(
                    online ? l10n.bookPayNote : l10n.bookClinicNote,
                    textAlign: TextAlign.center,
                    style: text.bodySmall,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _HoldBanner extends StatelessWidget {
  const _HoldBanner({required this.left, required this.total});

  final Duration left;
  final Duration total;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final fraction = total.inSeconds == 0
        ? 0.0
        : (left.inSeconds / total.inSeconds).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md + 2,
        vertical: AppSpace.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.tint(AppColors.warning),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          ExcludeSemantics(
            child: SizedBox.square(
              dimension: 36,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: fraction),
                duration: AppMotion.of(context, AppMotion.slow),
                builder: (context, value, icon) => CustomPaint(
                  painter: _CountdownPainter(fraction: value),
                  child: icon,
                ),
                child: const Icon(
                  Icons.schedule_rounded,
                  size: 16,
                  color: AppColors.warning,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.bookHeldFor(mmss(left)),
                  style: text.titleLarge?.copyWith(
                    fontSize: AppType.body.size,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  l10n.bookHeldBody,
                  style: text.bodySmall?.copyWith(color: AppColors.textBody),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CountdownPainter extends CustomPainter {
  const _CountdownPainter({required this.fraction});

  final double fraction;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(2);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      line..color = AppColors.warning.withValues(alpha: 0.25),
    );
    if (fraction <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * fraction,
      false,
      line
        ..color = AppColors.warning
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_CountdownPainter old) => old.fraction != fraction;
}

class _Summary extends StatelessWidget {
  const _Summary({required this.hold});

  final Hold hold;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final lang = Localizations.localeOf(context).languageCode;
    final d = hold.doctor;

    Widget row(String label, Widget value) => ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 40),
      child: Row(
        children: [
          Text(
            label,
            style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: value,
            ),
          ),
        ],
      ),
    );

    final strong = text.bodyMedium?.copyWith(
      color: AppColors.textStrong,
      fontWeight: FontWeight.w500,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg,
          vertical: AppSpace.xs,
        ),
        child: Column(
          children: [
            SizedBox(
              height: 56,
              child: Row(
                children: [
                  DoctorAvatar(initials: d.initials(lang), size: 36),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Text(
                      d.name(lang),
                      style: text.titleLarge?.copyWith(
                        fontSize: AppType.body.size,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            row(l10n.bookDate, Text(l10n.longDate(hold.start), style: strong)),
            row(
              l10n.bookTime,
              LtrText(timeRange(hold.start, hold.end), style: strong),
            ),
            const Divider(),
            SizedBox(
              height: 52,
              child: Row(
                children: [
                  Expanded(
                    child: Text(l10n.bookAmount, style: text.titleLarge),
                  ),
                  Text(
                    l10n.bookPrice(d.priceDzd),
                    style: text.headlineMedium?.copyWith(
                      color: AppColors.teal700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MethodCard extends StatelessWidget {
  const _MethodCard({
    required this.method,
    required this.selected,
    required this.onTap,
  });

  final PaymentMethod method;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final medium = AppMotion.of(context, AppMotion.medium);
    final (title, sub, icon) = switch (method) {
      PaymentMethod.edahabia => (
        l10n.bookEdahabia,
        l10n.bookViaChargily,
        Icons.credit_card_rounded,
      ),
      PaymentMethod.cib => (
        l10n.bookCib,
        l10n.bookViaChargily,
        Icons.credit_card_rounded,
      ),
      PaymentMethod.clinic => (
        l10n.bookClinicPay,
        l10n.bookClinicPaySub,
        Icons.payments_outlined,
      ),
    };

    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: medium,
          curve: AppMotion.curve,
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md + 2,
            vertical: AppSpace.sm + 2,
          ),
          decoration: BoxDecoration(
            color: selected ? AppColors.teal50 : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.card - 4),
            border: Border.all(
              color: selected ? AppColors.teal500 : AppColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: medium,
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: selected ? AppColors.surface : AppColors.sand100,
                  borderRadius: BorderRadius.circular(AppRadius.field),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: selected ? AppColors.teal600 : AppColors.textBody,
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: text.titleLarge?.copyWith(
                        fontSize: AppType.body.size,
                      ),
                    ),
                    Text(sub, style: text.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              AnimatedContainer(
                duration: medium,
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? AppColors.teal500 : AppColors.sand300,
                    width: 2,
                  ),
                ),
                child: AnimatedScale(
                  scale: selected ? 1 : 0,
                  duration: medium,
                  curve: AppMotion.pop,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: AppColors.teal500,
                      shape: BoxShape.circle,
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

class _Expired extends StatelessWidget {
  const _Expired({super.key, required this.onPickAnother});

  final VoidCallback onPickAnother;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.tint(AppColors.warning),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.timer_off_outlined,
                size: AppSpace.xxl,
                color: AppColors.warning,
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            Semantics(
              header: true,
              child: Text(
                l10n.bookExpiredTitle,
                textAlign: TextAlign.center,
                style: text.headlineMedium,
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              l10n.bookExpiredBody,
              textAlign: TextAlign.center,
              style: text.bodyLarge,
            ),
            const SizedBox(height: AppSpace.xl),
            FilledButton(
              onPressed: onPickAnother,
              child: Text(l10n.bookPickAnother),
            ),
          ],
        ),
      ),
    );
  }
}
