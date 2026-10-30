import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifeline_mobile/features/auth/domain/models/authenticated_user.dart';
import 'package:lifeline_mobile/features/auth/domain/repositories/auth_repository.dart';
import 'package:lifeline_mobile/features/auth/presentation/blocs/auth_cubit.dart';
import 'package:lifeline_mobile/features/cases/data/case_api_service.dart';
import 'package:lifeline_mobile/features/consultation/application/consultation_sync_service.dart';
import 'package:lifeline_mobile/features/consultation/data/local/local_consultation_repository.dart';
import 'package:lifeline_mobile/features/consultation/domain/models/consultation_draft.dart';
import 'package:lifeline_mobile/features/consultation/domain/models/consultation_guidance.dart';
import 'package:lifeline_mobile/features/consultation/domain/models/patient_draft.dart';
import 'package:lifeline_mobile/features/consultation/domain/models/saved_consultation.dart';
import 'package:lifeline_mobile/features/consultation/presentation/patient_fields_page.dart';
import 'package:lifeline_mobile/features/medical_bases/data/index/local_medical_knowledge_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _patient = PatientDraft(
  name: 'Ana',
  ageYears: 32,
  province: 'Lima',
  locationDescription: 'Parque',
  latitude: -12.0464,
  longitude: -77.0428,
  requesterPhone: '999111222',
);

final _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

final _recordedAt = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('lifeline_sync_');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('network failure and retry keep the same two uuids', () async {
    final repository = await _repository(directory, 'retry.db');
    final before = await _saveReady(repository, ownerKey: 'guest');
    final bodies = <Map<String, dynamic>>[];
    var attempts = 0;
    final service = _service(
      repository,
      MockClient((request) async {
        final body = _jsonBody(request);
        bodies.add(body);
        expect(request.headers['authorization'], isNull);
        expect(request.headers['idempotency-key'], body['idempotencyKey']);
        attempts++;
        if (attempts == 1) throw const SocketException('offline');
        return http.Response(
          jsonEncode({
            'id': 'backend-1',
            'idempotencyKey': body['idempotencyKey'],
            'helpRequested': false,
          }),
          201,
        );
      }),
    );

    final failed = await service.syncPending(ownerKey: 'guest');
    final afterFailure = await repository.get(before.id, ownerKey: 'guest');
    expect(failed.single.syncStatus, 'pending');
    expect(failed.single.errorMessage, isNull);
    expect(afterFailure?.mobileConsultationId, before.mobileConsultationId);
    expect(afterFailure?.idempotencyKey, before.idempotencyKey);
    expect(afterFailure?.backendConsultationId, isNull);
    expect(afterFailure?.syncStatus, 'pending');

    final sent = await service.syncPending(ownerKey: 'guest');
    final after = await repository.get(before.id, ownerKey: 'guest');
    expect(sent.single.syncStatus, 'confirmed');
    expect(bodies, hasLength(2));
    expect(bodies[0]['mobileConsultationId'], before.mobileConsultationId);
    expect(bodies[1]['mobileConsultationId'], before.mobileConsultationId);
    expect(bodies[0]['idempotencyKey'], before.idempotencyKey);
    expect(bodies[1]['idempotencyKey'], before.idempotencyKey);
    expect(after?.mobileConsultationId, before.mobileConsultationId);
    expect(after?.idempotencyKey, before.idempotencyKey);
    expect(after?.backendConsultationId, 'backend-1');
    expect(after?.syncStatus, 'confirmed');
    expect(await repository.list(ownerKey: 'guest'), hasLength(1));
  });

  test(
    'http 200 keeps the same uuids and does not create another row',
    () async {
      final repository = await _repository(directory, 'ok.db');
      final before = await _saveReady(
        repository,
        ownerKey: 'user:alice',
        helpRequested: true,
        patient: _patient,
      );
      var calls = 0;
      final service = _service(
        repository,
        MockClient((request) async {
          calls++;
          final body = _jsonBody(request);
          expect(body['mobileConsultationId'], before.mobileConsultationId);
          expect(body['idempotencyKey'], before.idempotencyKey);
          expect(request.headers['idempotency-key'], before.idempotencyKey);
          return http.Response(
            jsonEncode({'id': 'backend-200', 'helpRequested': true}),
            200,
          );
        }),
      );

      await service.syncPending(
        ownerKey: 'user:alice',
        citizenUserId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      );
      await service.syncPending(
        ownerKey: 'user:alice',
        citizenUserId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      );
      final after = await repository.get(before.id, ownerKey: 'user:alice');
      expect(calls, 1);
      expect(after?.mobileConsultationId, before.mobileConsultationId);
      expect(after?.idempotencyKey, before.idempotencyKey);
      expect(after?.backendConsultationId, 'backend-200');
      expect(after?.syncStatus, 'confirmed');
      expect(await repository.list(ownerKey: 'user:alice'), hasLength(1));
    },
  );

  test('helpRequested false sends a null patient', () async {
    final repository = await _repository(directory, 'no-help.db');
    final saved = await _saveReady(
      repository,
      ownerKey: 'guest',
      patient: _patient,
      professionalHelpRecommended: null,
    );
    late Map<String, dynamic> body;
    final service = _service(
      repository,
      MockClient((request) async {
        body = _jsonBody(request);
        return http.Response(jsonEncode({'id': 'backend-no-help'}), 201);
      }),
    );

    await service.syncPending(ownerKey: 'guest');
    final stored = await repository.get(saved.id, ownerKey: 'guest');
    expect(body['helpRequested'], isFalse);
    expect(body['patient'], isNull);
    expect(body['citizenUserId'], isNull);
    expect(body['photoStorageKey'], isNull);
    expect(body.containsKey('id'), isFalse);
    expect(jsonEncode(body).contains('requesterPhone'), isFalse);
    expect(jsonEncode(body).contains('999111222'), isFalse);
    expect(body['answer']['guidanceStatus'], 'GENERATED');
    expect(body['answer']['professionalHelpRecommended'], isFalse);
    expect(body['consultationRecordedAt'], matches(_recordedAt));
    expect(stored?.guidance?.professionalHelpRecommended, isNull);
    expect(stored?.patient?.requesterPhone, '999111222');
  });

  test(
    'helpRequested true sends the requester phone for case details',
    () async {
      final repository = await _repository(directory, 'help.db');
      await _saveReady(
        repository,
        ownerKey: 'user:alice',
        helpRequested: true,
        patient: _patient,
        priority: PreliminaryPriority.high,
        source: const MedicalSource(
          id: 'minsa',
          institution: 'MINSA',
          title: 'Guía',
          url: 'https://example.test/guia',
          edition: '2024',
        ),
      );
      late Map<String, dynamic> body;
      final service = _service(
        repository,
        MockClient((request) async {
          body = _jsonBody(request);
          expect(request.headers['authorization'], isNull);
          return http.Response(jsonEncode({'id': 'backend-help'}), 201);
        }),
      );

      await service.syncPending(
        ownerKey: 'user:alice',
        citizenUserId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      );
      expect(body['helpRequested'], isTrue);
      expect(body['citizenUserId'], 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
      expect(body['inputText'], 'Corte superficial');
      expect(body['photoStorageKey'], isNull);
      expect(body['patient']['name'], 'Ana');
      expect(body['patient']['ageYears'], 32);
      expect(body['patient']['province'], 'Lima');
      expect(body['patient']['locationDescription'], 'Parque');
      expect(body['patient']['latitude'], -12.0464);
      expect(body['patient']['longitude'], -77.0428);
      expect(body['patient']['phone'], '999111222');
      expect(body['requesterPhone'], '999111222');
      expect(body['patient'].containsKey('requesterPhone'), isFalse);
      expect(body['answer']['guidanceStatus'], 'GENERATED');
      expect(body['answer']['guidanceText'], 'Lavar la herida');
      expect(body['answer']['preliminaryPriority'], 'HIGH');
      expect(body['answer']['professionalHelpRecommended'], isTrue);
      expect(body['answer']['sourceReferences'], [
        {
          'institution': 'MINSA',
          'title': 'Guía',
          'url': 'https://example.test/guia',
        },
      ]);
      expect(body['consultationRecordedAt'], matches(_recordedAt));
    },
  );

  test('photo is uploaded in a second request using the backend id', () async {
    final repository = await _repository(directory, 'photo.db');
    final photo = File('${directory.path}${Platform.pathSeparator}wound.jpg');
    await photo.writeAsBytes([1, 2, 3, 4]);
    final before = await _saveReady(
      repository,
      ownerKey: 'guest',
      helpRequested: true,
      patient: _patient,
      photoPath: photo.path,
    );
    final paths = <String>[];
    final service = _service(
      repository,
      MockClient((request) async {
        paths.add(request.url.path);
        expect(request.headers['authorization'], isNull);
        if (request.url.path.endsWith('/photo')) {
          expect(request.headers['idempotency-key'], before.idempotencyKey);
          final payload = utf8.decode(request.bodyBytes, allowMalformed: true);
          expect(payload, contains('name="file"'));
          expect(payload.toLowerCase(), contains('image/jpeg'));
          return http.Response(jsonEncode({'storageKey': 'stored'}), 200);
        }
        return http.Response(jsonEncode({'id': 'backend-photo'}), 201);
      }),
    );

    final sent = await service.syncPending(ownerKey: 'guest');
    expect(paths, [
      '/api/v1/consultation-submissions',
      '/api/v1/consultation-submissions/backend-photo/photo',
    ]);
    expect(sent.single.syncStatus, 'confirmed');
    expect(sent.single.backendConsultationId, 'backend-photo');
  });

  test(
    'retry uploads only the photo when the backend id already exists',
    () async {
      final repository = await _repository(directory, 'photo-retry.db');
      final photo = File('${directory.path}${Platform.pathSeparator}wound.png');
      await photo.writeAsBytes([1, 2, 3]);
      final before = await _saveReady(
        repository,
        ownerKey: 'guest',
        helpRequested: true,
        patient: _patient,
        photoPath: photo.path,
      );
      var jsonCalls = 0;
      var photoCalls = 0;
      final service = _service(
        repository,
        MockClient((request) async {
          if (request.url.path.endsWith('/photo')) {
            expect(request.headers['idempotency-key'], before.idempotencyKey);
            photoCalls++;
            if (photoCalls == 1) throw const SocketException('offline');
            expect(
              request.url.path,
              '/api/v1/consultation-submissions/backend-photo/photo',
            );
            final payload = utf8.decode(
              request.bodyBytes,
              allowMalformed: true,
            );
            expect(payload, contains('name="file"'));
            expect(payload.toLowerCase(), contains('image/png'));
            return http.Response(jsonEncode({'storageKey': 'stored'}), 200);
          }
          jsonCalls++;
          return http.Response(jsonEncode({'id': 'backend-photo'}), 201);
        }),
      );

      final first = await service.syncPending(ownerKey: 'guest');
      final midway = await repository.get(before.id, ownerKey: 'guest');
      expect(jsonCalls, 1);
      expect(photoCalls, 1);
      expect(first.single.syncStatus, 'pending');
      expect(midway?.backendConsultationId, 'backend-photo');
      expect(midway?.mobileConsultationId, before.mobileConsultationId);
      expect(midway?.idempotencyKey, before.idempotencyKey);

      final second = await service.syncPending(ownerKey: 'guest');
      final after = await repository.get(before.id, ownerKey: 'guest');
      expect(jsonCalls, 1);
      expect(photoCalls, 2);
      expect(second.single.syncStatus, 'confirmed');
      expect(after?.mobileConsultationId, before.mobileConsultationId);
      expect(after?.idempotencyKey, before.idempotencyKey);
      expect(after?.backendConsultationId, 'backend-photo');
      expect(await repository.list(ownerKey: 'guest'), hasLength(1));
    },
  );

  test('photo 404 does not create another consultation', () async {
    final repository = await _repository(directory, 'photo-404.db');
    final photo = File('${directory.path}${Platform.pathSeparator}wound.webp');
    await photo.writeAsBytes([1, 2, 3]);
    final before = await _saveReady(
      repository,
      ownerKey: 'guest',
      photoPath: photo.path,
    );
    var jsonCalls = 0;
    final service = _service(
      repository,
      MockClient((request) async {
        if (request.url.path.endsWith('/photo')) {
          return http.Response('missing', 404);
        }
        jsonCalls++;
        return http.Response(jsonEncode({'id': 'backend-404'}), 201);
      }),
    );

    await service.syncPending(ownerKey: 'guest');
    await service.syncPending(ownerKey: 'guest');
    final after = await repository.get(before.id, ownerKey: 'guest');
    expect(jsonCalls, 1);
    expect(after?.syncStatus, 'pending');
    expect(after?.backendConsultationId, 'backend-404');
    expect(after?.mobileConsultationId, before.mobileConsultationId);
    expect(after?.idempotencyKey, before.idempotencyKey);
    expect(await repository.list(ownerKey: 'guest'), hasLength(1));
  });

  test('http 400 stays pending and keeps the same uuids', () async {
    final repository = await _repository(directory, 'bad.db');
    final before = await _saveReady(repository, ownerKey: 'guest');
    final keys = <String>[];
    final service = _service(
      repository,
      MockClient((request) async {
        final body = _jsonBody(request);
        keys.add(body['idempotencyKey'] as String);
        keys.add(body['mobileConsultationId'] as String);
        return http.Response(jsonEncode({'message': 'Datos inválidos'}), 400);
      }),
    );

    final first = await service.syncPending(ownerKey: 'guest');
    final second = await service.syncPending(ownerKey: 'guest');
    final after = await repository.get(before.id, ownerKey: 'guest');
    expect(first.single.errorMessage, 'Datos inválidos');
    expect(second.single.errorMessage, 'Datos inválidos');
    expect(after?.syncStatus, 'pending');
    expect(after?.backendConsultationId, isNull);
    expect(after?.mobileConsultationId, before.mobileConsultationId);
    expect(after?.idempotencyKey, before.idempotencyKey);
    expect(keys, [
      before.idempotencyKey,
      before.mobileConsultationId,
      before.idempotencyKey,
      before.mobileConsultationId,
    ]);
  });

  test('migration assigns stable uuids without deleting rows', () async {
    final databasePath = '${directory.path}${Platform.pathSeparator}v4.db';
    final old = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE consultations (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              owner_key TEXT NOT NULL,
              created_at TEXT NOT NULL,
              description TEXT NOT NULL,
              help_requested INTEGER NOT NULL,
              photo_path TEXT,
              audio_path TEXT,
              triage_json TEXT,
              patient_json TEXT NOT NULL,
              guidance_status TEXT NOT NULL,
              guidance_json TEXT,
              preliminary_priority TEXT,
              professional_help_recommended INTEGER
            )
          ''');
        },
      ),
    );
    await old.insert('consultations', {
      'owner_key': 'guest',
      'created_at': '2026-10-28T15:04:05.000Z',
      'description': 'Fila previa',
      'help_requested': 0,
      'patient_json': 'null',
      'guidance_status': 'pending',
    });
    await old.close();

    final repository = LocalConsultationRepository(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    addTearDown(repository.close);
    final first = (await repository.list(ownerKey: 'guest')).single;
    expect(first.draft.description, 'Fila previa');
    expect(first.syncStatus, 'pending');
    expect(first.backendConsultationId, isNull);
    expect(first.mobileConsultationId, matches(_uuidV4));
    expect(first.idempotencyKey, matches(_uuidV4));
    expect(first.mobileConsultationId, isNot(first.idempotencyKey));
    await repository.close();

    final reopened = LocalConsultationRepository(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    addTearDown(reopened.close);
    final second = (await reopened.list(ownerKey: 'guest')).single;
    expect(second.id, first.id);
    expect(second.mobileConsultationId, first.mobileConsultationId);
    expect(second.idempotencyKey, first.idempotencyKey);
    expect(await reopened.list(ownerKey: 'guest'), hasLength(1));
  });

  test('only the current owner is sent', () async {
    final repository = await _repository(directory, 'owners.db');
    final guest = await _saveReady(repository, ownerKey: 'guest');
    final user = await _saveReady(
      repository,
      ownerKey: 'user:alice',
      helpRequested: true,
      patient: _patient,
      description: 'Caso de Alice',
    );
    final descriptions = <String>[];
    final service = _service(
      repository,
      MockClient((request) async {
        final body = _jsonBody(request);
        descriptions.add(body['inputText'] as String);
        return http.Response(jsonEncode({'id': 'backend-guest'}), 201);
      }),
    );

    await service.syncPending(ownerKey: 'guest');
    final guestRow = await repository.get(guest.id, ownerKey: 'guest');
    final userRow = await repository.get(user.id, ownerKey: 'user:alice');
    expect(descriptions, ['Corte superficial']);
    expect(guestRow?.syncStatus, 'confirmed');
    expect(userRow?.syncStatus, 'pending');
    expect(userRow?.backendConsultationId, isNull);
    expect(userRow?.mobileConsultationId, user.mobileConsultationId);
    expect(userRow?.idempotencyKey, user.idempotencyKey);
  });

  test('guidance that is not ready is not sent', () async {
    final repository = await _repository(directory, 'pending-guidance.db');
    await _saveReady(
      repository,
      ownerKey: 'guest',
      guidanceStatus: GuidanceStatus.failed,
    );
    var calls = 0;
    final service = _service(
      repository,
      MockClient((request) async {
        calls++;
        return http.Response(jsonEncode({'id': 'should-not'}), 201);
      }),
    );

    final attempts = await service.syncPending(ownerKey: 'guest');
    expect(calls, 0);
    expect(attempts, isEmpty);
  });

  testWidgets('guest does not read cases after a confirmed send', (
    tester,
  ) async {
    final calls = <http.Request>[];
    final api = CaseApiService(
      MockClient((request) async {
        calls.add(request);
        return http.Response(
          jsonEncode([
            {
              'id': 'case-1',
              'consultationId': 'backend-1',
              'status': 'ASSIGNED',
            },
          ]),
          200,
        );
      }),
    );
    await tester.pumpWidget(
      _summaryApp(auth: _guestCubit(), cases: api, backendId: 'backend-1'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Envío confirmado.'), findsOneWidget);
    expect(calls, isEmpty);
  });

  testWidgets('a citizen sees the case status for the confirmed consultation', (
    tester,
  ) async {
    final calls = <http.Request>[];
    final api = CaseApiService(
      MockClient((request) async {
        calls.add(request);
        return http.Response(
          jsonEncode([
            {
              'id': 'case-1',
              'consultationId': 'backend-1',
              'status': 'ASSIGNED',
            },
          ]),
          200,
        );
      }),
    );
    final citizen = AuthCubit(_FixedAuthRepository(_citizen));
    await citizen.signIn('ana@example.com', 'secret');
    await tester.pumpWidget(
      _summaryApp(auth: citizen, cases: api, backendId: 'backend-1'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Asignado'), findsOneWidget);
    expect(find.text('Envío confirmado.'), findsNothing);
    expect(calls.single.url.path, '/api/v1/cases/me');
    expect(calls.single.headers['authorization'], 'Bearer citizen-token');
  });

  testWidgets('a failed case lookup leaves the confirmed send as confirmed', (
    tester,
  ) async {
    final api = CaseApiService(MockClient((_) async => http.Response('', 500)));
    final citizen = AuthCubit(_FixedAuthRepository(_citizen));
    await citizen.signIn('ana@example.com', 'secret');
    await tester.pumpWidget(
      _summaryApp(auth: citizen, cases: api, backendId: 'backend-1'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Envío confirmado.'), findsOneWidget);
    expect(find.text('Asignado'), findsNothing);
  });
}

Future<LocalConsultationRepository> _repository(
  Directory directory,
  String name,
) async {
  final repository = LocalConsultationRepository(
    factory: databaseFactoryFfi,
    databasePath: '${directory.path}${Platform.pathSeparator}$name',
  );
  addTearDown(repository.close);
  return repository;
}

Future<SavedConsultation> _saveReady(
  LocalConsultationRepository repository, {
  required String ownerKey,
  bool helpRequested = false,
  PatientDraft? patient,
  String? photoPath,
  String description = 'Corte superficial',
  PreliminaryPriority? priority = PreliminaryPriority.low,
  bool? professionalHelpRecommended = true,
  GuidanceStatus guidanceStatus = GuidanceStatus.ready,
  MedicalSource? source,
}) async {
  final id = await repository.saveDraft(
    ConsultationDraft(
      description: description,
      helpRequested: helpRequested,
      photoPath: photoPath,
    ),
    patient,
    ownerKey: ownerKey,
  );
  await repository.saveGuidance(
    id,
    ConsultationGuidance(
      status: guidanceStatus,
      message: 'Lavar la herida',
      preliminaryPriority: priority,
      professionalHelpRecommended: professionalHelpRecommended,
      sources: [?source],
    ),
    ownerKey: ownerKey,
  );
  return (await repository.get(id, ownerKey: ownerKey))!;
}

ConsultationSyncService _service(
  LocalConsultationRepository repository,
  http.Client client,
) => ConsultationSyncService(
  repository: repository,
  client: client,
  baseUrl: 'http://127.0.0.1:8080',
);

Map<String, dynamic> _jsonBody(http.Request request) =>
    jsonDecode(utf8.decode(request.bodyBytes)) as Map<String, dynamic>;

const _citizen = AuthenticatedUser(
  id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  email: 'ana@example.com',
  firstName: 'Ana',
  lastName: 'Paz',
  role: 'CITIZEN',
  token: 'citizen-token',
);

class _FixedAuthRepository implements AuthRepository {
  const _FixedAuthRepository(this.user);
  final AuthenticatedUser? user;

  @override
  Future<AuthenticatedUser> signIn(String email, String password) async =>
      user!;

  @override
  Future<AuthenticatedUser> registerCitizen(Map<String, dynamic> data) =>
      throw UnimplementedError();

  @override
  Future<AuthenticatedUser> registerMedicalProfessional(
    Map<String, dynamic> data,
  ) => throw UnimplementedError();

  @override
  Future<AuthenticatedUser?> restoreSession() async => user;

  @override
  Future<bool> unlock(String password) async => false;

  @override
  Future<void> updateSavedUser(AuthenticatedUser user) async {}

  @override
  Future<void> signOut() async {}
}

AuthCubit _guestCubit() {
  final cubit = AuthCubit(const _FixedAuthRepository(null));
  cubit.continueAsGuest();
  return cubit;
}

Widget _summaryApp({
  required AuthCubit auth,
  required CaseApiService cases,
  required String backendId,
}) => RepositoryProvider<CaseApiService>.value(
  value: cases,
  child: BlocProvider<AuthCubit>.value(
    value: auth,
    child: MaterialApp(
      home: ConsultationSummaryPage(
        draft: const ConsultationDraft(
          description: 'Corte superficial',
          helpRequested: true,
        ),
        patient: _patient,
        savedId: 7,
        initialGuidance: const ConsultationGuidance(
          status: GuidanceStatus.ready,
          message: 'Lavar la herida',
          professionalHelpRecommended: true,
        ),
        fromHistory: true,
        initialSyncStatus: 'confirmed',
        initialBackendConsultationId: backendId,
      ),
    ),
  ),
);
