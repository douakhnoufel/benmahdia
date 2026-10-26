import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';
import 'booking_format.dart';
import 'booking_models.dart';
import 'booking_repository.dart';
import 'booking_widgets.dart';

/// The receipt of a paid appointment (PRD 4.4): reference, doctor, time,
/// amount, method and payment date. A payment receipt, not a tax invoice.
/// The patient can copy it as text.
class ReceiptScreen extends ConsumerStatefulWidget {
  const ReceiptScreen({super.key, required this.appointment});

  final Appointment appointment;

  @override
  ConsumerState<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends ConsumerState<ReceiptScreen> {
  late Future<Receipt> _receipt = _load();

  Future<Receipt> _load() =>
      ref.read(bookingRepositoryProvider).receipt(widget.appointment);

  String _method(AppLocalizations l10n, PaymentMethod m) => switch (m) {
    PaymentMethod.edahabia => l10n.bookEdahabia,
    PaymentMethod.cib => l10n.bookCib,
    PaymentMethod.clinic => l10n.bookClinicPay,
  };

  List<(String, String)> _rows(AppLocalizations l10n, Receipt r, String lang) =>
      [
        (l10n.receiptNumber, r.number),
        (l10n.receiptDoctor, r.doctorName(lang)),
        (l10n.receiptVisit, '${l10n.longDate(r.start)} · ${hhmm(r.start)}'),
        (l10n.bookAmount, l10n.bookPrice(r.amountDzd)),
        (l10n.bookPayMethod, _method(l10n, r.method)),
        (l10n.receiptPaidOn, l10n.longDate(r.paidAt)),
        if (r.paymentRef case final ref?) (l10n.receiptRef, ref),
      ];

  Future<void> _copy(AppLocalizations l10n, Receipt r, String lang) async {
    final messenger = ScaffoldMessenger.of(context);
    final lines = [
      l10n.receiptTitle,
      for (final (label, value) in _rows(l10n, r, lang)) '$label : $value',
      l10n.receiptNote,
    ];
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    messenger.showSnackBar(SnackBar(content: Text(l10n.receiptCopied)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final lang = Localizations.localeOf(context).languageCode;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.receiptTitle)),
      body: SafeArea(
        child: FutureBuilder<Receipt>(
          future: _receipt,
          builder: (context, snapshot) {
            if (snapshot.error case final BookingRefused e) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.screenHorizontal),
                  child: InfoLine(text: l10n.bookingError(e), center: true),
                ),
              );
            }
            if (snapshot.hasError) {
              return LoadError(
                onRetry: () => setState(() {
                  _receipt = _load();
                }),
              );
            }
            final r = snapshot.data;
            if (r == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final rows = _rows(l10n, r, lang);
            return ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.screenHorizontal,
                AppSpace.lg,
                AppSpace.screenHorizontal,
                AppSpace.xl,
              ),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.lg,
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < rows.length; i++) ...[
                          if (i > 0) const Divider(),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpace.md,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    rows[i].$1,
                                    style: text.bodySmall?.copyWith(
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: AppSpace.md),
                                Flexible(
                                  flex: 2,
                                  child: Text(
                                    rows[i].$2,
                                    textAlign: TextAlign.end,
                                    style: text.bodyMedium?.copyWith(
                                      color: AppColors.textStrong,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.md),
                InfoLine(text: l10n.receiptNote, center: true),
                const SizedBox(height: AppSpace.lg),
                OutlinedButton.icon(
                  onPressed: () => _copy(l10n, r, lang),
                  icon: const Icon(Icons.copy_rounded),
                  label: Text(l10n.receiptCopy),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
