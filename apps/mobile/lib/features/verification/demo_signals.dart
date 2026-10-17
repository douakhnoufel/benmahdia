import 'dart:async';

import 'verification_models.dart';

// Stand-ins for the camera + on-device detection, so the verification
// screens can be seen and tested before the camera is wired. Replace them
// with the real detectors; the screens only depend on these signatures.

const _demoStep = Duration(seconds: 2);

/// Emits each liveness step as if the user had just completed it.
Stream<LivenessStep> demoLivenessSteps() => Stream<LivenessStep>.periodic(
  _demoStep,
  (i) => LivenessStep.values[i],
).take(LivenessStep.values.length);

/// Completes as if a whole card had become steady in the frame.
Future<void> demoCardDetected() => Future<void>.delayed(_demoStep);

/// Every photo check passes in the demo.
const demoIdQuality = IdQuality(sharp: true, noGlare: true, wholeCard: true);
