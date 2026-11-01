import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../application/incoming_notice.dart';

class FirebaseDeviceNotifications {
  String? _token;
  var _ready = false;

  Future<String?> currentToken() async => _ready ? _token : null;

  Future<void> start({
    required void Function(IncomingNotice notice) onForeground,
    required void Function(IncomingNotice notice) onOpened,
    void Function()? onTokenChanged,
  }) async {
    _ready = false;
    _token = null;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final allowed =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      if (!allowed) return;
      _token = await messaging.getToken();
      _ready = _token != null && _token!.isNotEmpty;
      messaging.onTokenRefresh.listen((token) {
        if (token.isEmpty || token == _token) return;
        _token = token;
        _ready = true;
        onTokenChanged?.call();
      });
      FirebaseMessaging.onMessage.listen((message) {
        final notice = _notice(message);
        if (notice.visibleText.isEmpty) return;
        onForeground(notice);
      });
      FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => onOpened(_notice(message)),
      );
      final initial = await messaging.getInitialMessage();
      if (initial != null) onOpened(_notice(initial));
    } catch (_) {
      _ready = false;
      _token = null;
    }
  }

  IncomingNotice _notice(RemoteMessage message) => IncomingNotice.from(
    title: message.notification?.title,
    body: message.notification?.body,
    data: message.data,
  );
}
