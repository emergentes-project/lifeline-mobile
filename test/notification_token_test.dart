import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifeline_mobile/features/notifications/application/notification_registration.dart';

void main() {
  test('citizen sends the device token with Authorization once', () async {
    final calls = <http.Request>[];
    final registration = _registration(
      MockClient((request) async {
        calls.add(request);
        return http.Response('', 201);
      }),
    );

    await registration.registerCitizen(
      deviceToken: 'fcm-1',
      userId: 'user-1',
      accessToken: 'jwt-citizen',
    );
    await registration.registerCitizen(
      deviceToken: 'fcm-1',
      userId: 'user-1',
      accessToken: 'jwt-citizen',
    );

    expect(calls, hasLength(1));
    expect(calls.single.method, 'POST');
    expect(calls.single.url.path, '/api/v1/notification-tokens');
    expect(calls.single.headers['authorization'], 'Bearer jwt-citizen');
    final body = jsonDecode(calls.single.body) as Map<String, dynamic>;
    expect(body['token'], 'fcm-1');
    expect(body.containsKey('consultationId'), isFalse);
  });

  test(
    'guest sends the token only for a confirmed help consultation',
    () async {
      final calls = <http.Request>[];
      final registration = _registration(
        MockClient((request) async {
          calls.add(request);
          return http.Response('', 200);
        }),
      );

      final sent = await registration.registerGuest(
        deviceToken: 'fcm-guest',
        helpRequested: true,
        confirmed: true,
        consultationId: 'backend-1',
      );
      final repeated = await registration.registerGuest(
        deviceToken: 'fcm-guest',
        helpRequested: true,
        confirmed: true,
        consultationId: 'backend-1',
      );

      expect(sent, isTrue);
      expect(repeated, isFalse);
      expect(calls, hasLength(1));
      expect(calls.single.headers['authorization'], isNull);
      final body =
          jsonDecode(utf8.decode(calls.single.bodyBytes))
              as Map<String, dynamic>;
      expect(body['token'], 'fcm-guest');
      expect(body['consultationId'], 'backend-1');
    },
  );

  test('guest does not send a token when help was not requested', () async {
    var calls = 0;
    final registration = _registration(
      MockClient((request) async {
        calls++;
        return http.Response('', 201);
      }),
    );

    final declined = await registration.registerGuest(
      deviceToken: 'fcm-guest',
      helpRequested: false,
      confirmed: true,
      consultationId: 'backend-1',
    );
    final pending = await registration.registerGuest(
      deviceToken: 'fcm-guest',
      helpRequested: true,
      confirmed: false,
      consultationId: 'backend-1',
    );

    expect(declined, isFalse);
    expect(pending, isFalse);
    expect(calls, 0);
  });
}

NotificationRegistration _registration(http.Client client) =>
    NotificationRegistration(
      client: client,
      sent: MemorySentNotificationTokens(),
      baseUrl: 'http://127.0.0.1:8080',
    );
