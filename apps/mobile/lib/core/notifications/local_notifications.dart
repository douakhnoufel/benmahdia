import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../features/auth/auth_repository.dart';

/// Notifications the phone schedules itself: appointment reminders
/// (PRD 4.3), and later medication and daily-check reminders (PRD 5.3, 5.4).
/// They work offline and nothing passes through Apple or Google push
/// servers. Callers keep the text neutral: never a drug, a doctor or the
/// clinic on the lock screen (PRD 8.3).
abstract interface class LocalNotifications {
  /// Asks the patient to allow notifications. True when allowed.
  Future<bool> requestPermission();

  /// Shows [title] and [body] at [at], a clinic wall-clock time
  /// (Africa/Algiers). Scheduling an [id] again replaces it.
  Future<void> schedule({
    required int id,
    required DateTime at,
    required String title,
    required String body,
  });

  Future<void> cancel(int id);

  /// The ids still waiting to be shown.
  Future<Set<int>> pending();
}

/// The phone's notifications when `API_BASE_URL` is set; with sample data
/// (and in tests) nothing is scheduled.
final localNotificationsProvider = Provider<LocalNotifications>((ref) {
  if (apiBaseUrl.isEmpty) return const NoLocalNotifications();
  return PluginLocalNotifications();
});

class NoLocalNotifications implements LocalNotifications {
  const NoLocalNotifications();

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> schedule({
    required int id,
    required DateTime at,
    required String title,
    required String body,
  }) async {}

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<Set<int>> pending() async => const {};
}

class PluginLocalNotifications implements LocalNotifications {
  PluginLocalNotifications([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  Future<void>? _ready;
  late final tz.Location _clinic;

  Future<void> _init() => _ready ??= () async {
    tzdata.initializeTimeZones();
    _clinic = tz.getLocation('Africa/Algiers');
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // Asked later, after the first booking, not at app start.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
  }();

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  @override
  Future<bool> requestPermission() async {
    await _init();
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      return await ios?.requestPermissions(alert: true, sound: true) ?? false;
    }
    return await _android?.requestNotificationsPermission() ?? false;
  }

  @override
  Future<void> schedule({
    required int id,
    required DateTime at,
    required String title,
    required String body,
  }) async {
    await _init();
    final when = tz.TZDateTime(
      _clinic,
      at.year,
      at.month,
      at.day,
      at.hour,
      at.minute,
    );
    // Exact when Android allows it (PRD 4.3: within a minute), otherwise
    // the system may deliver it a little late rather than not at all.
    final exact = await _android?.canScheduleExactNotifications() ?? true;
    await _plugin.zonedSchedule(
      id: id,
      scheduledDate: when,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'reminders',
          'Rappels · تذكيرات',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  @override
  Future<void> cancel(int id) async {
    await _init();
    await _plugin.cancel(id: id);
  }

  @override
  Future<Set<int>> pending() async {
    await _init();
    final requests = await _plugin.pendingNotificationRequests();
    return {for (final r in requests) r.id};
  }
}
