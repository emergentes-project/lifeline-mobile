import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../application/incoming_notice.dart';

@pragma('vm:entry-point')
Future<void> lifelineBackgroundMessage(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) await Firebase.initializeApp();
  // Android displays the notification payload. Do not produce a second local notice here.
}

class FirebaseDeviceNotifications {
  String? _token;
  var _ready = false;
  var _configured = false;
  Future<void>? _starting;
  StreamSubscription<String>? _tokenRefresh;
  StreamSubscription<RemoteMessage>? _messages;
  StreamSubscription<RemoteMessage>? _opened;
  String? configurationError;

  Future<String?> currentToken() async {
    if (!_configured) return null;
    try {
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        return null;
      }
      _token = await FirebaseMessaging.instance.getToken();
      _ready = _token?.isNotEmpty == true;
      return _ready ? _token : null;
    } catch (_) { return null; }
  }

  Future<void> rotateToken() async {
    if (!_configured) return;
    try { await FirebaseMessaging.instance.deleteToken(); } catch (_) {}
    _token = null;
    _ready = false;
  }

  Future<void> start({
    required void Function(IncomingNotice notice) onForeground,
    required void Function(IncomingNotice notice) onOpened,
    void Function()? onTokenChanged,
  }) {
    return _starting ??= _start(onForeground: onForeground, onOpened: onOpened,
      onTokenChanged: onTokenChanged).whenComplete(() { _starting = null; });
  }

  Future<void> _start({
    required void Function(IncomingNotice notice) onForeground,
    required void Function(IncomingNotice notice) onOpened,
    void Function()? onTokenChanged,
  }) async {
    await dispose();
    _ready = false;
    _token = null;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      _configured = true;
      configurationError = null;
      FirebaseMessaging.onBackgroundMessage(lifelineBackgroundMessage);
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
      _tokenRefresh = messaging.onTokenRefresh.listen((token) {
        if (token.isEmpty || token == _token) return;
        _token = token;
        _ready = true;
        onTokenChanged?.call();
      });
      _messages = FirebaseMessaging.onMessage.listen((message) {
        final notice = _notice(message);
        if (notice.visibleText.isEmpty) return;
        onForeground(notice);
      });
      _opened = FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => onOpened(_notice(message)),
      );
      final initial = await messaging.getInitialMessage();
      if (initial != null) onOpened(_notice(initial));
    } catch (_) {
      _ready = false;
      _token = null;
      configurationError = _configured ? 'No se pudo conectar con el servicio de avisos.'
          : 'Este paquete no tiene configuradas las notificaciones remotas.';
      debugPrint(configurationError);
    }
  }

  Future<void> dispose() async {
    await _tokenRefresh?.cancel();
    await _messages?.cancel();
    await _opened?.cancel();
    _tokenRefresh = null;
    _messages = null;
    _opened = null;
  }

  IncomingNotice _notice(RemoteMessage message) => IncomingNotice.from(
    title: message.notification?.title,
    body: message.notification?.body,
    data: message.data,
  );
}
