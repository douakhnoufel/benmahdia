import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_route.dart';
import '../../theme/app_tokens.dart';
import 'book_confirm_screen.dart';
import 'book_doctor_screen.dart';
import 'book_done_screen.dart';
import 'book_slot_screen.dart';
import 'my_appointments_screen.dart';

/// Opens booking: doctor, then day and time, then confirm and pay.
// TODO(booking): only verified patients may book (PRD 4.2); gate this once
// the account status comes from the backend.
void openBooking(BuildContext context) {
  final navigator = Navigator.of(context);
  final reduced = AppMotion.reduced(context);
  void push(Widget page) =>
      unawaited(navigator.push<void>(appRoute(page, reduced: reduced)));
  void home() => navigator.popUntil((route) => route.isFirst);

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
                  onHome: home,
                  onAppointments: () {
                    home();
                    openAppointments(context);
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
      appRoute(
        MyAppointmentsScreen(onBookNew: () => openBooking(context)),
        reduced: AppMotion.reduced(context),
      ),
    ),
  );
}
