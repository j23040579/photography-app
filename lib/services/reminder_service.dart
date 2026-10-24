import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../domain/models.dart';

/// Native, one-shot, offline reminders. No timers must remain alive in Dart.
class ReminderService {
  ReminderService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool available = false;
  String status = 'Reminders have not been initialized.';

  Future<void> initialize() async {
    if (!Platform.isAndroid && !Platform.isWindows) {
      status = 'Native reminders are available on Android and Windows.';
      return;
    }
    try {
      tz_data.initializeTimeZones();
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
      final initialized = await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('notification_icon'),
          windows: WindowsInitializationSettings(
            appName: 'Photo Graph',
            appUserModelId: 'PhotoGraph.PhotographyApp',
            guid: 'fbdce6e7-b563-41cb-bf76-32ecf29b4c19',
          ),
        ),
      );
      available = initialized ?? false;
      status = available
          ? 'Reminders use your device’s local time.'
          : 'Your device could not enable notifications.';
    } catch (_) {
      available = false;
      status =
          'Notifications are unavailable. Check system notification settings.';
    }
  }

  Future<void> scheduleAlbum(
    Album album, {
    bool requestPermission = true,
  }) async {
    final at = album.reminderAt;
    if (at == null) {
      await cancelAlbum(album.id);
      return;
    }
    if (!at.isAfter(DateTime.now())) {
      throw ArgumentError('Choose a reminder time in the future.');
    }
    if (!available) throw StateError(status);
    if (Platform.isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final allowed = requestPermission
          ? await android?.requestNotificationsPermission()
          : await android?.areNotificationsEnabled();
      if (allowed == false) {
        throw StateError(
          'Allow Photo Graph notifications in Android settings to set a reminder.',
        );
      }
    }
    // The fixed hash is stable across launches (String.hashCode is not a
    // persistent identifier). Reusing it makes edits replace the prior alarm.
    await _plugin.cancel(id: notificationId(album.id));
    await _plugin.zonedSchedule(
      id: notificationId(album.id),
      title: 'A little moment for ${album.title}',
      body: album.prompts.isEmpty
          ? 'Your album is waiting. Take a photo to remember today.'
          : album.prompts
                .firstWhere(
                  (prompt) => album.reminderPromptId != null
                      ? prompt.id == album.reminderPromptId
                      : !prompt.completed,
                  orElse: () => album.prompts.first,
                )
                .text,
      scheduledDate: tz.TZDateTime.from(at, tz.local),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'photo_graph_memories',
          'Photo reminders',
          channelDescription: 'A reminder to capture photos for your albums',
          importance: Importance.high,
          priority: Priority.high,
        ),
        windows: WindowsNotificationDetails(),
      ),
      // Avoid exact-alarm special permissions. Android may deliver later under
      // battery optimisations, as explained in the reminder UI/documentation.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: album.id,
    );
  }

  Future<void> cancelAlbum(String albumId) async {
    if (!available) return;
    await _plugin.cancel(id: notificationId(albumId));
  }

  /// Re-establish future alarms after a restore/reinstall without duplicates.
  Future<void> restoreReminders(Iterable<Album> albums) async {
    if (!available) return;
    for (final album in albums) {
      if (album.reminderAt?.isAfter(DateTime.now()) ?? false) {
        try {
          await scheduleAlbum(album, requestPermission: false);
        } catch (_) {
          status =
              'Some reminders could not be restored. Open the album to '
              'set its reminder again, and check notification permissions.';
        }
      }
    }
  }

  static int notificationId(String id) {
    var hash = 0x811c9dc5;
    for (final unit in id.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}
