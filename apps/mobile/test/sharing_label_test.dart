import 'package:benmahdia_mobile/widgets/sharing_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

Future<void> _pump(WidgetTester tester, SharingKind kind) async {
  await pumpApp(tester, Scaffold(body: SharingLabel(kind)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('only you, in Arabic and French', (tester) async {
    await _pump(tester, SharingKind.onlyYou);
    expect(find.text('أنت فقط'), findsOneWidget);
    expect(directionOf(tester, SharingLabel), TextDirection.rtl);
    await useFrench(tester);
    expect(find.text('Vous seul(e)'), findsOneWidget);
  });

  testWidgets('your doctor sees this, in Arabic and French', (tester) async {
    await _pump(tester, SharingKind.doctor);
    expect(find.text('طبيبك يرى هذا'), findsOneWidget);
    await useFrench(tester);
    expect(find.text('Votre médecin voit ceci'), findsOneWidget);
  });

  testWidgets('is announced as one label', (tester) async {
    await _pump(tester, SharingKind.doctor);
    expect(find.bySemanticsLabel('طبيبك يرى هذا'), findsOneWidget);
  });
}
