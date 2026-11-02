import 'package:benmahdia_mobile/widgets/sharing_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

// The label that says who can see a piece of the patient's data
// (habit-tracking design: "explain what the doctor can see").

Future<void> _pump(WidgetTester tester) => pumpApp(
  tester,
  const Scaffold(
    body: Column(
      children: [
        SharingLabel(sharing: Sharing.onlyYou),
        SharingLabel(sharing: Sharing.doctorSees),
      ],
    ),
  ),
);

void main() {
  testWidgets('both labels read in Arabic and in French', (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();

    expect(find.text('أنت فقط ترى هذا'), findsOne);
    expect(find.text('طبيبك يرى هذا'), findsOne);

    await useFrench(tester);
    await tester.pumpAndSettle();

    expect(find.text('Vous seul voyez ceci'), findsOne);
    expect(find.text('Votre médecin voit ceci'), findsOne);
  });

  testWidgets('each label is one semantics node a screen reader can read', (
    tester,
  ) async {
    await _pump(tester);
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(find.byType(SharingLabel).first),
      matchesSemantics(label: 'أنت فقط ترى هذا'),
    );
  });

  testWidgets('a lock marks what stays on the phone, an eye what is shared', (
    tester,
  ) async {
    await _pump(tester);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.lock_outline_rounded), findsOne);
    expect(find.byIcon(Icons.visibility_outlined), findsOne);
  });
}
