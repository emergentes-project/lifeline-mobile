import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifeline_mobile/features/auth/data/local/secure_session_storage.dart';
import 'package:lifeline_mobile/features/auth/data/remote/auth_api_service.dart';

void main() {
  test('sign in reads backend user and token', () async {
    final api = AuthApiService(
      MockClient((request) async {
        expect(request.url.path, '/api/v1/authentication/sign-in');
        return http.Response(
          jsonEncode({
            'user': {
              'id': 'id-1',
              'email': 'ana@example.com',
              'firstName': 'Ana',
              'lastName': 'Rojas',
              'role': 'CITIZEN',
              'phone': '999111222',
            },
            'token': 'jwt',
          }),
          200,
        );
      }),
    );
    final user = await api.signIn('ana@example.com', 'password');
    expect(user.fullName, 'Ana Rojas');
    expect(user.token, 'jwt');
    expect(user.phone, '999111222');
    expect(user.toJson()['user']['phone'], '999111222');
  });

  test(
    'sign in distinguishes invalid credentials and backend failure',
    () async {
      Future<String> failureFor(int status) async {
        final api = AuthApiService(
          MockClient((_) async => http.Response('{}', status)),
        );
        try {
          await api.signIn('ana@example.com', 'password');
          fail('Expected sign in to fail');
        } on AuthApiException catch (error) {
          return error.message;
        }
      }

      expect(
        await failureFor(401),
        contains('Correo o contraseña incorrectos'),
      );
      expect(await failureFor(500), contains('fallo interno'));
    },
  );

  test('sign in explains when the published web app is stopped', () async {
    final api = AuthApiService(
      MockClient((_) async => http.Response('This web app is stopped', 403)),
    );
    await expectLater(
      api.signIn('ana@example.com', 'password'),
      throwsA(
        isA<AuthApiException>().having(
          (error) => error.message,
          'message',
          contains('servidor está detenido'),
        ),
      ),
    );
  });

  test('sign in explains connection failure', () async {
    final api = AuthApiService(
      MockClient((_) async => throw const SocketException('Offline')),
    );
    await expectLater(
      api.signIn('ana@example.com', 'password'),
      throwsA(
        isA<AuthApiException>().having(
          (error) => error.message,
          'message',
          contains('No se pudo conectar'),
        ),
      ),
    );
  });

  test('offline verifier depends on password and salt', () {
    final salt = List<int>.filled(32, 7);
    expect(
      deriveUnlockKey('correcta', salt),
      deriveUnlockKey('correcta', salt),
    );
    expect(
      deriveUnlockKey('otra', salt),
      isNot(deriveUnlockKey('correcta', salt)),
    );
  });
}
