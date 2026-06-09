import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tzData;

class NotificationService {
  static final FlutterLocalNotificationsPlugin notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    // 1. Initialize Time Zones for accurate scheduling
    tzData.initializeTimeZones();

    // 2. Set up Android Initialization Settings
    // Using the default app icon located in the mipmap folder
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // 3. Set up Apple (iOS/macOS) Initialization Settings
    const DarwinInitializationSettings darwinSettings =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    // 4. Combine Settings
    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    // 5. Initialize the plugin and listen for notification taps
    await notificationsPlugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        print("Notification tapped!");
      },
    );

    // 6. Request permission to show notifications on Android 13+
    final androidImplementation = notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidImplementation?.requestNotificationsPermission();
    await androidImplementation?.requestExactAlarmsPermission();
  }

  // 🔔 Method to schedule a notification at a specific time
  static Future<void> scheduleNotification(
    int id,
    DateTime scheduledTime,
    String title,
    String body,
  ) async {
    // 1. Calculate the exact time difference to bypass UTC timezone shifting bugs
    Duration timeDifference = scheduledTime.difference(DateTime.now());
    if (timeDifference.isNegative) {
      timeDifference = const Duration(
        seconds: 2,
      ); // Fallback to avoid past-time errors
    }

    final tzScheduledTime = tz.TZDateTime.now(tz.local).add(timeDifference);

    await notificationsPlugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tzScheduledTime,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'medicine_reminder_channel_v2', // ⚠️ Changed ID to force Android to create a new loud channel!
          'Medicine Reminders', // Channel Name
          channelDescription: 'Notifications for taking scheduled medicines',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
        ),
        iOS: DarwinNotificationDetails(
          presentSound: true,
          presentAlert: true,
          presentBadge: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }
}
