import 'dart:io';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_reminders/src/reminder_plan.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// Seam over the notifications plugin so scheduling logic is testable.
abstract interface class NotificationsBackend {
  Future<void> init();
  Future<bool> requestPermission();

  /// [at] is an absolute instant (local wall-clock converted to UTC).
  Future<void> schedule(int id, DateTime at, String title, String body);
  Future<void> cancel(int id);
}

class PluginNotificationsBackend implements NotificationsBackend {
  PluginNotificationsBackend([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// Android notification channel. Created at init so it is listed in the
  /// system's notification settings before the first reminder fires.
  static const channel = AndroidNotificationChannel(
    'expiry_reminders',
    'Expiry reminders',
    description: 'Reminders before your documents expire',
  );

  /// Monochrome status-bar icon (res/drawable, kept from resource shrinking
  /// by res/raw/keep_notification_icons.xml). A full-colour launcher icon
  /// would render as a white square.
  static const smallIcon = '@drawable/ic_stat_reminder';

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'expiry_reminders',
      'Expiry reminders',
      channelDescription: 'Reminders before your documents expire',
      icon: smallIcon,
      // Hide the document name on a secure lock screen.
      visibility: NotificationVisibility.private,
    ),
    iOS: DarwinNotificationDetails(),
  );

  @override
  Future<void> init() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(smallIcon),
        // Ask for permission explicitly from Settings, not at launch.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
        ),
      ),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
  }

  /// Android 13+ shows the POST_NOTIFICATIONS prompt (once; afterwards this
  /// returns the current state without UI). Older Android versions grant it
  /// at install time and return whether notifications are enabled.
  @override
  Future<bool> requestPermission() async {
    if (Platform.isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await android?.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    return await ios?.requestPermissions(alert: true, sound: true) ?? false;
  }

  @override
  Future<void> schedule(int id, DateTime at, String title, String body) =>
      _plugin.zonedSchedule(
        id: id,
        // An absolute instant in UTC: fires at the intended local time
        // without loading the timezone database (tz.UTC needs no
        // initializeTimeZones() call, which would add ~100 ms and 400 KB at
        // startup). The boot receiver restores it after a reboot. A DST
        // change between now and the reminder may shift it by an hour,
        // which is fine for a 30/7-day notice.
        scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
        notificationDetails: _details,
        // Inexact (Android 12+): no SCHEDULE_EXACT_ALARM / USE_EXACT_ALARM
        // permission (both need a Play policy declaration); a reminder a few
        // minutes late is fine for a 30/7-day notice. Allow-while-idle so
        // Doze doesn't hold it for hours.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: title,
        body: body,
      );

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);
}

/// [ReminderScheduler] using local notifications only.
class LocalReminderScheduler implements ReminderScheduler {
  LocalReminderScheduler({
    NotificationsBackend? backend,
    DateTime Function()? clock,
    @visibleForTesting bool? isSupportedPlatform,
    RedactedLogger? logger,
  }) : _backend = backend ?? PluginNotificationsBackend(),
       _clock = clock ?? DateTime.now,
       _platformOk =
           isSupportedPlatform ??
           (!kIsWeb && (Platform.isAndroid || Platform.isIOS)),
       _log = logger ?? RedactedLogger('reminders');

  final NotificationsBackend _backend;
  final DateTime Function() _clock;
  final bool _platformOk;
  final RedactedLogger _log;
  Future<void>? _ready;

  /// Shown when the user (or Android 13+'s default) denied notifications.
  static const notificationsOff = AppFailure(
    FailureCode.permissionDenied,
    heading: 'Notifications are off for IDSnap',
    message:
        'Expiry dates are saved, but reminders need notifications. Open '
        "your phone's Settings › Apps › IDSnap › Notifications, allow them, "
        'then turn on Expiry reminders again.',
    action: FailureAction.none,
  );

  /// Initialises once; a failed init is retried on the next call instead of
  /// failing forever.
  Future<void> _ensureInit() => _ready ??= _init();

  Future<void> _init() async {
    try {
      await _backend.init();
    } on Object {
      _ready = null;
      rethrow;
    }
  }

  @override
  Future<EngineCapability> capability() async => _platformOk
      ? const EngineCapability(available: true, worksOffline: true)
      : const EngineCapability(
          available: false,
          worksOffline: true,
          note: 'Reminders are available on Android and iOS.',
        );

  @override
  Future<Result<void>> requestPermission() async {
    if (!_platformOk) return const Ok(null);
    try {
      await _ensureInit();
      final granted = await _backend.requestPermission();
      return granted ? const Ok(null) : const Err(notificationsOff);
    } on Object catch (e, st) {
      _log.error('permission_failed', {'type': e.runtimeType.toString()});
      return Err(
        AppFailure(
          FailureCode.unknown,
          cause: e,
          stackTrace: st,
          heading: "Couldn't turn on notifications",
          message:
              'Your expiry dates are saved, but reminders are not set. '
              'Restart IDSnap and turn on Settings › Your data › Expiry '
              'reminders again.',
          action: FailureAction.contactSupport,
        ),
      );
    }
  }

  @override
  Future<Result<void>> scheduleExpiry(Document document) async {
    if (!_platformOk) return const Ok(null);
    try {
      await _ensureInit();
      await _cancelAll(document.id);
      final plans = planExpiryReminders(document, _clock());
      for (final plan in plans) {
        await _backend.schedule(plan.id, plan.at, plan.title, plan.body);
      }
      _log.info('scheduled', {'count': plans.length});
      return const Ok(null);
    } on Object catch (e, st) {
      _log.error('schedule_failed', {'type': e.runtimeType.toString()});
      return Err(
        AppFailure(
          FailureCode.unknown,
          cause: e,
          stackTrace: st,
          heading: 'Reminder not set',
          message:
              'The expiry date is saved, but the phone refused to schedule '
              'the reminder. Turn Settings › Your data › Expiry reminders '
              'off and on to try again.',
          action: FailureAction.contactSupport,
        ),
      );
    }
  }

  @override
  Future<Result<void>> cancel(String documentId) async {
    if (!_platformOk) return const Ok(null);
    try {
      await _ensureInit();
      await _cancelAll(documentId);
      return const Ok(null);
    } on Object catch (e, st) {
      _log.error('cancel_failed', {'type': e.runtimeType.toString()});
      return Err(
        AppFailure(
          FailureCode.unknown,
          cause: e,
          stackTrace: st,
          heading: 'Reminder not removed',
          message:
              'A reminder for this document may still appear. Turn Settings '
              '› Your data › Expiry reminders off to remove all reminders.',
          action: FailureAction.none,
        ),
      );
    }
  }

  Future<void> _cancelAll(String documentId) async {
    for (final days in reminderOffsets) {
      await _backend.cancel(reminderId(documentId, days));
    }
  }
}
