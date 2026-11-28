import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:lifeline_mobile/features/auth/presentation/blocs/auth_state.dart';
import 'package:lifeline_mobile/features/consultation/application/consultation_sync_service.dart';
import 'package:lifeline_mobile/features/consultation/application/consultation_sync_coordinator.dart';
import 'package:lifeline_mobile/features/consultation/data/local/local_consultation_repository.dart';
import 'package:lifeline_mobile/features/consultation/domain/models/consultation_draft.dart';
import 'package:lifeline_mobile/features/consultation/domain/models/consultation_guidance.dart';

void main() {
  sqfliteFfiInit();
  late Directory folder;
  late LocalConsultationRepository repository;
  setUp(() async {
    folder = await Directory.systemTemp.createTemp('lifeline-reliability-');
    repository = LocalConsultationRepository(factory: databaseFactoryFfi, databasePath: '${folder.path}/local.db');
  });
  tearDown(() async {
    await repository.close();
    final resolved = await folder.resolveSymbolicLinks();
    final tempRoot = await Directory.systemTemp.resolveSymbolicLinks();
    if (!path.isWithin(tempRoot, resolved) || !path.basename(resolved).startsWith('lifeline-reliability-')) {
      throw StateError('Refusing to remove a directory outside this test fixture');
    }
    await Directory(resolved).delete(recursive: true);
  });
  Future<int> save({GuidanceStatus status = GuidanceStatus.ready, String owner = 'guest'}) =>
      repository.saveCompleteConsultation(draft: const ConsultationDraft(description: 'Synthetic request', helpRequested: true),
          patient: null, guidance: ConsultationGuidance(status: status, message: 'Synthetic guidance'), ownerKey: owner);

  test('help survives model failure and sends its real guidance status', () async {
    final id = await save(status: GuidanceStatus.modelUnavailable);
    final sync = ConsultationSyncService(repository: repository, client: MockClient((request) async {
      expect(jsonDecode(request.body)['answer']['guidanceStatus'], 'FAILED');
      return http.Response(jsonEncode({'id': 'server-1', 'guestAccessToken': 'scoped-capability'}), 201);
    }));
    await sync.syncPending(ownerKey: 'guest');
    final row = await repository.get(id, ownerKey: 'guest');
    expect(row!.syncStatus, 'confirmed');
    expect(row.guestAccessToken, 'scoped-capability');
  });

  test('simultaneous screens share publication and keep one logical request', () async {
    await save();
    final started = Completer<void>(), release = Completer<void>();
    var calls = 0;
    final sync = ConsultationSyncService(repository: repository, client: MockClient((request) async {
      calls++;
      started.complete();
      await release.future;
      return http.Response('{"id":"server-1"}', 201);
    }));
    final first = sync.syncPending(ownerKey: 'guest');
    await started.future;
    final second = sync.syncPending(ownerKey: 'guest');
    release.complete();
    await Future.wait([first, second]);
    expect(calls, 1);
  });

  test('response loss followed by a process restart preserves the complete request', () async {
    final id = await save();
    Map<String, dynamic>? original;
    final before = ConsultationSyncService(repository: repository, client: MockClient((request) async {
      original = jsonDecode(request.body) as Map<String, dynamic>;
      throw const SocketException('Response was lost after acceptance');
    }));
    await before.syncPending(ownerKey: 'guest');
    await repository.close();
    repository = LocalConsultationRepository(factory: databaseFactoryFfi, databasePath: '${folder.path}/local.db');
    final after = ConsultationSyncService(repository: repository, client: MockClient((request) async {
      expect(jsonDecode(request.body), original);
      return http.Response('{"id":"same-server-id"}', 200);
    }));
    await after.syncPending(ownerKey: 'guest');
    expect((await repository.get(id, ownerKey: 'guest'))!.syncStatus, 'confirmed');
    expect(await repository.list(ownerKey: 'guest'), hasLength(1));
  });

  test('tracking is scoped, persisted and ignores an older server snapshot', () async {
    final id = await save();
    var reads = 0;
    final sync = ConsultationSyncService(repository: repository, client: MockClient((request) async {
      if (request.method == 'POST') return http.Response('{"id":"server-1","guestAccessToken":"guest-proof"}', 201);
      expect(request.headers['x-consultation-token'], 'guest-proof');
      expect(request.headers.containsKey('authorization'), false);
      reads++;
      return http.Response(jsonEncode({'consultationId': 'server-1', 'caseId': 'case-1',
        'caseStatus': reads == 1 ? 'CLOSED' : 'AVAILABLE',
        'updatedAt': reads == 1 ? '2026-11-27T12:00:00' : '2026-11-27T11:00:00'}), 200);
    }));
    await sync.syncPending(ownerKey: 'guest');
    await sync.refreshTracking(ownerKey: 'guest');
    await sync.refreshTracking(ownerKey: 'guest');
    final row = await repository.get(id, ownerKey: 'guest');
    expect(row!.caseStatus, 'CLOSED');
    expect(row.caseId, 'case-1');
    expect(row.syncStatus, 'confirmed');
    expect(await repository.get(id, ownerKey: 'user:another'), isNull);
  });

  test('network restoration automatically drains pending work without a screen action', () async {
    await save();
    var auth = const AuthState(status: AuthStatus.loading);
    final authChanges = StreamController<AuthState>.broadcast();
    final network = StreamController<bool>.broadcast();
    final done = Completer<void>();
    var posts = 0;
    final sync = ConsultationSyncService(repository: repository, client: MockClient((request) async {
      if (request.method == 'POST') {
        posts++;
        return http.Response('{"id":"server-1","guestAccessToken":"guest-proof"}', 201);
      }
      return http.Response('{"consultationId":"server-1","caseId":null,"caseStatus":null,"updatedAt":"2026-11-27T12:00:00"}', 200);
    }));
    final coordinator = ConsultationSyncCoordinator(repository: repository, sync: sync,
      currentAuth: () => auth, authChanges: authChanges.stream, connectivityChanges: network.stream,
      interval: const Duration(hours: 1), onSynced: (_, _, _) async { if (!done.isCompleted) done.complete(); });
    coordinator.start();
    coordinator.setOnline(false);
    auth = const AuthState(status: AuthStatus.guest);
    authChanges.add(auth);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(posts, 0);
    network.add(true);
    network.add(true);
    await done.future.timeout(const Duration(seconds: 5));
    expect(posts, 1);
    await coordinator.dispose();
    await authChanges.close();
    await network.close();
  });
}
