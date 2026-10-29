import 'dart:convert';

import 'package:benmahdia_mobile/features/booking/booking_repository.dart';
import 'package:benmahdia_mobile/features/recovery/api_recovery_repository.dart';
import 'package:benmahdia_mobile/features/booking/fake_booking_repository.dart';
import 'package:benmahdia_mobile/features/recovery/fake_recovery_repository.dart';
import 'package:benmahdia_mobile/features/recovery/milestone_screen.dart';
import 'package:benmahdia_mobile/features/recovery/recovery_models.dart';
import 'package:benmahdia_mobile/features/recovery/recovery_repository.dart';
import 'package:benmahdia_mobile/features/recovery/recovery_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'helpers.dart';

// Milestone celebrations (PRD 5.1).

void main() {
  group('the ladder', () {
    test('reached milestones, then every year', () {
      expect(reachedMilestone(0), 0);
      expect(reachedMilestone(2), 1);
      expect(reachedMilestone(13), 7);
      expect(reachedMilestone(364), 180);
      expect(reachedMilestone(800), 730);
    });

    test('a milestone is pending until seen; a relapse starts over', () {
      final a = Addiction(
        id: 'a',
        type: AddictionType.alcohol,
        start: DateTime(2026, 10, 1),
        longestPastDays: 0,
        pastDays: 0,
      );
      final now = DateTime(2026, 10, 17);
      expect(a.pendingMilestone(now), 14);
      expect(a.withMilestoneSeen(14).pendingMilestone(now), isNull);
      expect(a.withMilestoneSeen(14).withGoal(28).milestoneSeen, 14);
      expect(a.withMilestoneSeen(14).relapsed(now).milestoneSeen, 0);
    });
  });

  test('the API records the celebration and reads it back', () async {
    final sent = <http.Request>[];
    final api = ApiRecoveryRepository(
      baseUrl: Uri.parse('https://api.test/'),
      token: () => 'token',
      refresh: () async => false,
      rest: FakeRecoveryRepository(),
      client: MockClient((r) async {
        sent.add(r);
        return http.Response(
          jsonEncode({
            'id': 'a-1',
            'type': 'alcohol',
            'profile': null,
            'goal_days': null,
            'substance': null,
            'clean_since': '2026-10-03T18:00:00Z',
            'longest_past_days': 0,
            'past_days': 0,
            'review_status': 'confirmed',
            'goal': 28,
            'milestone': 14,
            'milestone_seen': 14,
          }),
          200,
        );
      }),
    );
    final a = Addiction(
      id: 'a-1',
      type: AddictionType.alcohol,
      start: DateTime(2026, 10, 3),
      longestPastDays: 0,
      pastDays: 0,
    );
    final updated = await api.markMilestoneSeen(a);
    expect(sent.single.method, 'POST');
    expect(sent.single.url.path, '/v1/me/addictions/a-1/milestone/seen');
    expect(updated.milestoneSeen, 14);
  });

  group('celebration', () {
    // The sample counter starts 9 days before construction with day 7
    // celebrated; moving the clock 5 days on reaches day 14.
    late DateTime now;
    late FakeRecoveryRepository repo;

    Future<void> open(WidgetTester tester, {int daysLater = 5}) async {
      now = DateTime(2026, 10, 17, 17, 10);
      repo = FakeRecoveryRepository(clock: () => now);
      now = now.add(Duration(days: daysLater));
      await pumpApp(
        tester,
        const RecoveryScreen(),
        overrides: [
          recoveryRepositoryProvider.overrideWithValue(repo),
          bookingRepositoryProvider.overrideWithValue(
            FakeBookingRepository(clock: () => now),
          ),
        ],
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows once, in Arabic, and is remembered', (tester) async {
      await open(tester);
      expect(find.byType(MilestoneScreen), findsOneWidget);
      expect(find.text('أحسنت!'), findsOneWidget);
      expect(find.text('14'), findsOneWidget);
      expect(directionOf(tester, MilestoneScreen), TextDirection.rtl);

      await tester.tap(find.text('متابعة'));
      await tester.pumpAndSettle();
      expect(find.byType(MilestoneScreen), findsNothing);
      expect(repo.storedAddictions.single.milestoneSeen, 14);
    });

    testWidgets('French wording and the streak\'s badges', (tester) async {
      await open(tester);
      await useFrench(tester);
      await tester.pumpAndSettle();
      expect(find.text('Bravo !'), findsOneWidget);
      expect(find.textContaining('14 jours sans'), findsOneWidget);
      for (final badge in ['1 jour', '3 jours', '7 jours', '14 jours']) {
        expect(find.widgetWithText(Chip, badge), findsOneWidget);
      }
      expect(find.widgetWithText(Chip, '30 jours'), findsNothing);
    });

    testWidgets('nothing to celebrate, nothing shown', (tester) async {
      await open(tester, daysLater: 0);
      expect(find.byType(MilestoneScreen), findsNothing);
      expect(find.byType(RecoveryScreen), findsOneWidget);
    });
  });
}
