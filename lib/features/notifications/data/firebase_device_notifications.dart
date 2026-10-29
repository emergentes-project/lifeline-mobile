import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class FirebaseDeviceNotifications {
  String? _token;
  var _ready = false;

  Future<String?> currentToken() async => _ready ? _token : null;

  Future<void> start({
    required void Function(String title, String body) onForeground,
    required void Function() onOpenHistory,
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
        final title = message.notification?.title?.trim() ?? '';
        final body = message.notification?.body?.trim() ?? '';
        if (title.isEmpty && body.isEmpty) return;
        onForeground(title, body);
      });
      FirebaseMessaging.onMessageOpenedApp.listen((_) => onOpenHistory());
      final initial = await messaging.getInitialMessage();
      if (initial != null) onOpenHistory();
    } catch (_) {
      _ready = false;
      _token = null;
    }
  }
}
