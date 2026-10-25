import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_route.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_tokens.dart';
import '../home/home_scope.dart';
import '../profile/identity_models.dart';
import '../profile/identity_repository.dart';
import '../profile/profile_card.dart';
import '../profile/profile_flow.dart';
import 'book_confirm_screen.dart';
import 'book_doctor_screen.dart';
import 'book_done_screen.dart';
import 'book_slot_screen.dart';
import 'my_appointments_screen.dart';

/// Opens booking: doctor, then day and time, then confirm and pay. Callers go
/// through [openAppointments], which keeps it closed until the clinic has
/// approved the patient (PRD 4.2); the server refuses it as well.
void openBooking(BuildContext context) {
  final navigator = Navigator.of(context);
  final reduced = AppMotion.reduced(context);
  void push(Widget page) =>
      unawaited(navigator.push<void>(appRoute(page, reduced: reduced)));
  void home() => navigator.popUntil((route) => route.isFirst);
  // Inside the home shell, its tabs show the new booking after a refresh.
  final shell = HomeShellScope.maybeOf(context);

  push(
    BookDoctorScreen(
      onNext: (doctor) => push(
        BookSlotScreen(
          doctor: doctor,
          onNext: (hold) => push(
            BookConfirmScreen(
              hold: hold,
              onExpired: () => navigator.pop(),
              onDone: (appointment) => push(
                BookDoneScreen(
                  appointment: appointment,
                  onHome: () {
                    home();
                    shell?.refresh();
                  },
                  onAppointments: () {
                    home();
                    if (shell == null) return openAppointments(context);
                    shell
                      ..refresh()
                      ..select(HomeTab.appointments);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Opens the patient's appointments.
void openAppointments(BuildContext context) {
  final navigator = Navigator.of(context);
  unawaited(
    navigator.push<void>(
      appRoute(const AppointmentsGate(), reduced: AppMotion.reduced(context)),
    ),
  );
}

/// The appointments, with booking locked until the profile is approved. A
/// patient who has not finished "Complete your profile" can still look
/// around: the card says what is missing, and "book" leads to it.
class AppointmentsGate extends ConsumerWidget {
  const AppointmentsGate({super.key, this.showBack});

  /// See [MyAppointmentsScreen.showBack].
  final bool? showBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Unknown (loading, offline) does not lock: the server decides anyway.
    final identity = ref.watch(identityStateProvider).valueOrNull;
    final locked = identity == null || identity.approved ? null : identity;
    final l10n = AppLocalizations.of(context);

    void completeProfile() => openProfile(context);
    void refresh() => ref.invalidate(identityStateProvider);

    return MyAppointmentsScreen(
      showBack: showBack,
      banner: locked == null
          ? null
          : ProfileCard(
              state: locked,
              onComplete: completeProfile,
              onRefresh: refresh,
            ),
      onBookNew: locked == null
          ? () => openBooking(context)
          : locked.status == IdStatus.declared
          ? () => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.profileCardDeclaredBody)),
            )
          : completeProfile,
    );
  }
}
