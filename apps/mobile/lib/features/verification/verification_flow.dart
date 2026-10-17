import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_route.dart';
import '../../theme/app_tokens.dart';
import 'demo_signals.dart';
import 'id_capture_screen.dart';
import 'review_screen.dart';
import 'selfie_screen.dart';

/// Opens the identity check in PRD order: live selfie, then the ID card
/// front and back, then review and submit.
// TODO(verification): swap the demo signals for the camera + on-device
// detectors, and upload on submit.
void openVerification(BuildContext context) {
  final navigator = Navigator.of(context);
  final reduced = AppMotion.reduced(context);
  void push(Widget page) =>
      unawaited(navigator.push<void>(appRoute(page, reduced: reduced)));

  push(
    SelfieScreen(
      steps: demoLivenessSteps(),
      onCaptured: () => push(
        IdCaptureScreen(
          cardDetected: demoCardDetected,
          onDone: () => push(
            ReviewScreen(
              quality: demoIdQuality,
              onRetake: () => navigator.pop(),
            ),
          ),
        ),
      ),
    ),
  );
}
