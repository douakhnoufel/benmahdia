import 'package:benmahdia_mobile/core/notifications/local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('with sample data nothing reaches the phone', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifications = container.read(localNotificationsProvider);
    expect(notifications, isA<NoLocalNotifications>());
    expect(await notifications.requestPermission(), isFalse);
    await notifications.schedule(
      id: 1,
      at: DateTime(2026, 11, 2, 9),
      title: 't',
      body: 'b',
    );
    expect(await notifications.pending(), isEmpty);
  });
}
