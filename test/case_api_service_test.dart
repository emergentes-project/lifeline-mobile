import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifeline_mobile/features/cases/data/case_api_service.dart';
import 'package:lifeline_mobile/features/cases/domain/models/managed_case.dart';

void main() {
  test('case workflow uses server routes and bearer token', () async {
    final calls = <http.Request>[];
    final api = CaseApiService(
      MockClient((request) async {
        calls.add(request);
        if (request.url.path.endsWith('/history')) {
          return http.Response('[]', 200);
        }
        if (request.url.path.endsWith('/cases') ||
            request.url.path.endsWith('/cases/me')) {
          return http.Response('[]', 200);
        }
        return http.Response(
          jsonEncode({
            'id': 'case-1',
            'consultationId': 'consult-1',
            'status': 'ASSIGNED',
          }),
          200,
        );
      }),
    );
    await api.listAvailable('jwt');
    await api.listAssignedToMe('jwt');
    await api.listForCitizen('jwt');
    await api.assign('jwt', 'case-1');
    await api.changeStatus('jwt', 'case-1', CaseStatus.inProgress);
    await api.close('jwt', 'case-1', 'Atendido');
    await api.history('jwt', 'case-1');

    expect(calls.map((request) => request.url.path), [
      '/api/v1/cases',
      '/api/v1/cases',
      '/api/v1/cases/me',
      '/api/v1/cases/case-1/assign',
      '/api/v1/cases/case-1/status',
      '/api/v1/cases/case-1/close',
      '/api/v1/cases/case-1/history',
    ]);
    expect(calls[0].url.queryParameters['status'], 'AVAILABLE');
    expect(
      calls[1].url.queryParameters['assignmentRelation'],
      'ASSIGNED_TO_ME',
    );
    expect(
      calls.every(
        (request) => request.headers['authorization'] == 'Bearer jwt',
      ),
      isTrue,
    );
    expect(jsonDecode(calls[4].body)['newStatus'], 'IN_PROGRESS');
    expect(jsonDecode(calls[5].body)['observation'], 'Atendido');
  });

  test('conflict is reported without assuming operation succeeded', () async {
    final api = CaseApiService(MockClient((_) async => http.Response('', 409)));
    expect(
      () => api.assign('jwt', 'case-1'),
      throwsA(
        isA<CaseApiException>().having(
          (error) => error.conflict,
          'conflict',
          true,
        ),
      ),
    );
  });

  test('consultation detail maps patient, orientation and sources', () async {
    final api = CaseApiService(
      MockClient(
        (_) async => http.Response(
          jsonEncode({
            'inputText': 'Herida en brazo',
            'requesterPhone': '987654321',
            'helpRequested': true,
            'hasPhoto': false,
            'patient': {
              'name': 'Ana',
              'ageYears': 34,
              'province': 'Lima',
              'latitude': -12.0,
              'longitude': -77.0,
            },
            'answer': {
              'guidanceStatus': 'COMPLETED',
              'guidanceText': 'Cubrir la herida',
              'preliminaryPriority': 'HIGH',
              'professionalHelpRecommended': true,
              'sourceReferences': [
                {
                  'institution': 'MINSA',
                  'title': 'Guía',
                  'url': 'https://example.org',
                },
              ],
            },
          }),
          200,
        ),
      ),
    );

    final result = await api.consultation('jwt', 'consult-1');
    expect(result.requesterPhone, '987654321');
    expect(result.patient?.name, 'Ana');
    expect(result.answer?.preliminaryPriority, 'HIGH');
    expect(result.answer?.sources.single.institution, 'MINSA');
  });

  test('paged case request sends filters and reads totals', () async {
    late http.Request captured;
    final api = CaseApiService(
      MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'items': [],
            'page': 2,
            'size': 10,
            'totalElements': 24,
            'totalPages': 3,
          }),
          200,
        );
      }),
    );
    final result = await api.listPage(
      'jwt',
      citizen: false,
      assignedToMe: true,
      filters: const CaseFilters(
        status: CaseStatus.inProgress,
        priority: 'HIGH',
        province: 'Lima',
      ),
      page: 2,
      size: 10,
    );
    expect(captured.url.path, '/api/v1/cases/paged');
    expect(captured.url.queryParameters, containsPair('status', 'IN_PROGRESS'));
    expect(captured.url.queryParameters, containsPair('priority', 'HIGH'));
    expect(captured.url.queryParameters, containsPair('province', 'Lima'));
    expect(
      captured.url.queryParameters,
      containsPair('assignmentRelation', 'ASSIGNED_TO_ME'),
    );
    expect(result.totalPages, 3);
    expect(result.totalElements, 24);
  });
}
