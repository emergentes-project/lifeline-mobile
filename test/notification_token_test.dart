import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifeline_mobile/features/auth/data/local/secure_session_storage.dart';
import 'package:lifeline_mobile/features/auth/data/remote/auth_api_service.dart';
import 'package:lifeline_mobile/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:lifeline_mobile/features/auth/domain/models/authenticated_user.dart';
import 'package:lifeline_mobile/features/auth/presentation/blocs/auth_state.dart';
import 'package:lifeline_mobile/features/consultation/domain/models/consultation_draft.dart';
import 'package:lifeline_mobile/features/consultation/domain/models/saved_consultation.dart';
import 'package:lifeline_mobile/features/notifications/application/delivery_confirmation_notices.dart';
import 'package:lifeline_mobile/features/notifications/application/incoming_notice.dart';
import 'package:lifeline_mobile/features/notifications/application/notification_registration.dart';
import 'package:lifeline_mobile/features/notifications/application/open_case_notice.dart';
import 'package:lifeline_mobile/features/notifications/application/publish_notification_token.dart';

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

  test(
    'citizen post accepts 204 and another account registers again',
    () async {
      var calls = 0;
      final registration = _registration(
        MockClient((request) async {
          calls++;
          return http.Response('', 204);
        }),
      );

      final first = await registration.registerCitizen(
        deviceToken: 'fcm-1',
        userId: 'user-1',
        accessToken: 'jwt-1',
      );
      final repeat = await registration.registerCitizen(
        deviceToken: 'fcm-1',
        userId: 'user-1',
        accessToken: 'jwt-1',
      );
      final other = await registration.registerCitizen(
        deviceToken: 'fcm-1',
        userId: 'user-2',
        accessToken: 'jwt-2',
      );

      expect(first, isTrue);
      expect(repeat, isFalse);
      expect(other, isTrue);
      expect(calls, 2);
    },
  );

  test('sign out deletes the token before revoking the jwt', () async {
    final order = <String>[];
    final sent = MemorySentNotificationTokens();
    await sent.save('citizen:user-1', 'fcm-1');
    final client = MockClient((request) async {
      order.add(request.method);
      if (request.method == 'DELETE') {
        expect(request.url.path, '/api/v1/notification-tokens');
        expect(request.headers['authorization'], 'Bearer jwt-1');
        expect(jsonDecode(request.body)['token'], 'fcm-1');
        throw const SocketException('sin red');
      }
      expect(request.url.path, '/api/v1/authentication/sign-out');
      expect(request.headers['authorization'], 'Bearer jwt-1');
      return http.Response('', 204);
    });
    final registration = NotificationRegistration(
      client: client,
      sent: sent,
      baseUrl: 'http://127.0.0.1:8080',
    );
    final repository = AuthRepositoryImpl(
      api: AuthApiService(client),
      sessions: _MemorySessions(_citizen(id: 'user-1', token: 'jwt-1'), order),
      beforeRemoteSignOut: (accessToken) =>
          registration.revoke(deviceToken: 'fcm-1', accessToken: accessToken),
    );

    await repository.signOut();

    expect(order, ['DELETE', 'clear', 'POST']);
    expect(await sent.matches('citizen:user-1', 'fcm-1'), isFalse);
  });

  test('sign out does not delete the token without a jwt', () async {
    var deletes = 0;
    final repository = AuthRepositoryImpl(
      api: AuthApiService(
        MockClient((request) async {
          if (request.method == 'DELETE') deletes++;
          return http.Response('', 204);
        }),
      ),
      sessions: _MemorySessions(_citizen(id: 'user-1', token: ''), []),
      beforeRemoteSignOut: (_) async => deletes++,
    );

    await repository.signOut();

    expect(deletes, 0);
  });

  test('a citizen session does not register a guest token', () async {
    final calls = <http.Request>[];
    final registration = _registration(
      MockClient((request) async {
        calls.add(request);
        return http.Response('', 201);
      }),
    );

    await dispatchNotificationToken(
      registration: registration,
      deviceToken: 'fcm-1',
      auth: AuthState(
        status: AuthStatus.authenticated,
        user: _citizen(id: 'citizen-1', token: 'jwt-1'),
      ),
      consultations: [
        _saved(id: 7, help: true, status: 'confirmed', backendId: 'backend-1'),
      ],
    );

    expect(calls, hasLength(1));
    expect(calls.single.headers['authorization'], 'Bearer jwt-1');
    final body = jsonDecode(calls.single.body) as Map<String, dynamic>;
    expect(body['token'], 'fcm-1');
    expect(body.containsKey('consultationId'), isFalse);
  });

  test('tapping the notice opens the received case id', () async {
    final notice = IncomingNotice.from(
      title: 'Asignado',
      body: 'Un profesional tomó tu caso',
      data: {'caseId': 'case-42', 'guidanceText': 'dato clínico'},
    );
    expect(notice.visibleText, 'Asignado\nUn profesional tomó tu caso');
    expect(notice.visibleText.contains('dato clínico'), isFalse);

    String? loaded;
    final opened = await destinationForCaseNotice(
      citizenSignedIn: true,
      caseId: notice.caseId,
      loadCase: (id) async => loaded = id,
    );
    final hidden = await destinationForCaseNotice(
      citizenSignedIn: true,
      caseId: 'case-other',
      loadCase: (_) async => throw StateError('forbidden'),
    );

    expect(loaded, 'case-42');
    expect(opened.caseId, 'case-42');
    expect(hidden.caseId, isNull);
  });

  test('confirmed delivery notice appears once', () async {
    final shown = <String>[];
    final notices = DeliveryConfirmationNotices((_, message) async {
      shown.add(message);
    });

    await notices.announce(
      [_saved(id: 1, help: true, status: 'pending')],
      [_saved(id: 1, help: true, status: 'confirmed')],
    );
    await notices.announce(
      [_saved(id: 1, help: true, status: 'confirmed')],
      [_saved(id: 1, help: true, status: 'confirmed')],
    );
    await notices.announce(
      [_saved(id: 2, help: false, status: 'pending')],
      [_saved(id: 2, help: false, status: 'confirmed')],
    );

    expect(shown, ['Envío confirmado']);
  });
}

AuthenticatedUser _citizen({required String id, required String token}) =>
    AuthenticatedUser(
      id: id,
      email: 'ana@example.com',
      firstName: 'Ana',
      lastName: 'Paz',
      role: 'CITIZEN',
      token: token,
    );

SavedConsultation _saved({
  required int id,
  required bool help,
  required String status,
  String? backendId,
}) => SavedConsultation(
  id: id,
  createdAt: DateTime.utc(2026, 1, 1),
  draft: ConsultationDraft(description: 'dolor', helpRequested: help),
  patient: null,
  guidance: null,
  mobileConsultationId: 'mobile-$id',
  idempotencyKey: 'idem-$id',
  backendConsultationId: backendId,
  syncStatus: status,
);

class _MemorySessions implements SessionStore {
  _MemorySessions(this.user, this.order);
  AuthenticatedUser? user;
  final List<String> order;

  @override
  Future<AuthenticatedUser?> read() async => user;

  @override
  Future<void> clear() async {
    order.add('clear');
    user = null;
  }

  @override
  Future<void> save(AuthenticatedUser user, String password) async {}

  @override
  Future<bool> verify(String password) async => false;

  @override
  Future<void> updateUser(AuthenticatedUser user) async {}
}

NotificationRegistration _registration(http.Client client) =>
    NotificationRegistration(
      client: client,
      sent: MemorySentNotificationTokens(),
      baseUrl: 'http://127.0.0.1:8080',
    );
