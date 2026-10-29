import 'dart:convert';
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
