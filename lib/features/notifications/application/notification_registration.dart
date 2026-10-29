import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';

abstract class SentNotificationTokens {
  Future<bool> matches(String scope, String token);
  Future<void> save(String scope, String token);
}

class MemorySentNotificationTokens implements SentNotificationTokens {
  final _values = <String, String>{};

  @override
  Future<bool> matches(String scope, String token) async =>
      _values[scope] == token;

  @override
  Future<void> save(String scope, String token) async {
    _values[scope] = token;
  }
}

class SecureSentNotificationTokens implements SentNotificationTokens {
  SecureSentNotificationTokens(this.storage);
  final FlutterSecureStorage storage;
  final _cache = <String, String>{};

  @override
  Future<bool> matches(String scope, String token) async {
    final cached = _cache[scope];
    if (cached != null) return cached == token;
    try {
      final stored = await storage.read(key: _key(scope));
      if (stored == null) return false;
      _cache[scope] = stored;
      return stored == token;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> save(String scope, String token) async {
    _cache[scope] = token;
    try {
      await storage.write(key: _key(scope), value: token);
    } catch (_) {}
  }

  String _key(String scope) =>
      'lifeline_notification_${scope.replaceAll(':', '_')}';
}

class NotificationRegistration {
  NotificationRegistration({
    required this.client,
    required this.sent,
    this.baseUrl = ApiConfig.baseUrl,
    this.timeout = const Duration(seconds: 12),
  });

  final http.Client client;
  final SentNotificationTokens sent;
  final String baseUrl;
  final Duration timeout;

  Future<bool> registerCitizen({
    required String deviceToken,
    required String userId,
    required String accessToken,
  }) {
    if (deviceToken.isEmpty || accessToken.isEmpty) return Future.value(false);
    return _post(
      scope: 'citizen:$userId',
      deviceToken: deviceToken,
      accessToken: accessToken,
    );
  }

  Future<bool> registerGuest({
    required String deviceToken,
    required bool helpRequested,
    required bool confirmed,
    required String? consultationId,
  }) {
    if (!helpRequested || !confirmed || deviceToken.isEmpty) {
      return Future.value(false);
    }
    final id = consultationId;
    if (id == null || id.isEmpty) return Future.value(false);
    return _post(
      scope: 'guest:$id',
      deviceToken: deviceToken,
      consultationId: id,
    );
  }

  Future<bool> _post({
    required String scope,
    required String deviceToken,
    String? accessToken,
    String? consultationId,
  }) async {
    if (await sent.matches(scope, deviceToken)) return false;
    final body = <String, dynamic>{
      'token': deviceToken,
      'consultationId': ?consultationId,
    };
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (accessToken != null) {
      headers['Authorization'] = 'Bearer $accessToken';
    }
    try {
      final response = await client
          .post(
            _uri('/api/v1/notification-tokens'),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(timeout);
      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.created) {
        return false;
      }
      await sent.save(scope, deviceToken);
      return true;
    } on TimeoutException {
      return false;
    } on SocketException {
      return false;
    } on http.ClientException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Uri _uri(String path) {
    final root = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$root$path');
  }
}
