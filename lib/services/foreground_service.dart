import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../models/strings.dart';

class VisionForegroundService {
  VisionForegroundService._();

  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'bagdar_fg',
        channelName: 'Bagdar Navigation',
        channelDescription: 'Keeps navigation running in background',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
        eventAction: ForegroundTaskEventAction.nothing(),
      ),
    );

    _initialized = true;
  }

  static Future<bool> start() async {
    if (!_initialized) await init();

    final isRunning = await FlutterForegroundTask.isRunningService;
    if (isRunning) return true;

    await FlutterForegroundTask.startService(
      serviceId: 1001,
      notificationTitle: S.get('fg_notification_title'),
      notificationText: S.get('fg_notification_body'),
      callback: _startCallback,
    );

    debugPrint('ForegroundService: started=true');
    return true;
  }

  static Future<void> updateNotification(String text) async {
    final isRunning = await FlutterForegroundTask.isRunningService;
    if (!isRunning) return;
    await FlutterForegroundTask.updateService(
      notificationTitle: S.get('fg_notification_title'),
      notificationText: text,
    );
  }

  static Future<void> stop() async {
    final isRunning = await FlutterForegroundTask.isRunningService;
    if (!isRunning) return;
    await FlutterForegroundTask.stopService();
    debugPrint('ForegroundService: stopped');
  }
}

@pragma('vm:entry-point')
void _startCallback() {
  FlutterForegroundTask.setTaskHandler(_EmptyTaskHandler());
}

class _EmptyTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}
