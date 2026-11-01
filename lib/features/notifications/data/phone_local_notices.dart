import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class PhoneLocalNotices {
  final _plugin = FlutterLocalNotificationsPlugin();
  var _ready = false;

  Future<void> show(int id, String message) async {
    try {
      if (!_ready) {
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
        await _plugin.initialize(
          settings: const InitializationSettings(
            android: AndroidInitializationSettings('@mipmap/ic_launcher'),
            iOS: DarwinInitializationSettings(
              requestAlertPermission: false,
              requestBadgePermission: false,
              requestSoundPermission: false,
            ),
          ),
        );
        _ready = true;
      }
      await _plugin.show(
        id: id,
        title: message,
        body: message,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'lifeline_delivery',
            'Envíos',
            channelDescription: 'Aviso cuando un envío queda confirmado',
          ),
        ),
      );
    } catch (_) {}
  }
}
