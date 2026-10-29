import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifeline_mobile/features/auth/data/remote/profile_api_service.dart';

void main() {
  test(
    'loads and updates citizen account and profile using bearer token',
    () async {
      final requests = <http.Request>[];
      final api = ProfileApiService(
        MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({'firstName': 'Ana', 'city': 'Lima'}),
            200,
          );
        }),
      );

      await api.account('token');
      await api.roleProfile('token', citizen: true);
      await api.updateAccount('token', {
        'firstName': 'Ana',
        'lastName': 'Pérez',
        'phone': null,
      });
      await api.updateRoleProfile('token', {
        'city': 'Lima',
        'district': 'Lince',
        'address': 'Av. 1',
      }, citizen: true);

      expect(requests.map((request) => request.url.path), [
        '/api/v1/users/me',
        '/api/v1/citizen-profiles/me',
        '/api/v1/users/me',
        '/api/v1/citizen-profiles/me',
      ]);
      expect(requests.map((request) => request.method), [
        'GET',
        'GET',
        'PUT',
        'PUT',
      ]);
      expect(
        requests.every(
          (request) => request.headers['authorization'] == 'Bearer token',
        ),
        isTrue,
      );
      expect(jsonDecode(requests.last.body)['district'], 'Lince');
    },
  );

  test('uses the medical endpoint and reports server failure', () async {
    final api = ProfileApiService(
      MockClient((request) async {
        expect(request.url.path, '/api/v1/medical-profiles/me');
        return http.Response('', 503);
      }),
    );
    expect(
      () => api.roleProfile('token', citizen: false),
      throwsA(isA<ProfileApiException>()),
    );
  });
}
