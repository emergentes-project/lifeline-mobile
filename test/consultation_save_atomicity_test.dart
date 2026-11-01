import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifeline_mobile/features/consultation/application/consultation_sync_service.dart';
import 'package:lifeline_mobile/features/consultation/data/local/local_consultation_repository.dart';
import 'package:lifeline_mobile/features/consultation/domain/models/consultation_draft.dart';
import 'package:lifeline_mobile/features/consultation/domain/models/consultation_guidance.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('lifeline_atomic_');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test(
    'an interruption between the two writes does not leave a pending row',
    () async {
      final repository = _repository(directory, 'draft.db');
      final id = await repository.saveDraft(
        const ConsultationDraft(description: 'Corte', helpRequested: true),
        null,
        ownerKey: 'guest',
      );
      await repository.close();

      final reopened = _repository(directory, 'draft.db');
      final row = await reopened.get(id, ownerKey: 'guest');
      expect(row?.syncStatus, 'draft');
      expect(row?.guidance?.isReady, isNot(true));
      final calls = <http.Request>[];
      await ConsultationSyncService(
        repository: reopened,
        client: MockClient((request) async {
          calls.add(request);
          return http.Response('', 201);
        }),
      ).syncPending(ownerKey: 'guest');
      expect(calls, isEmpty);
    },
  );

  test(
    'a failed complete save leaves no finalized consultation and keeps the uuids of one that committed',
    () async {
      final media = Directory(path.join(directory.path, 'media'));
      await media.create();
      final repository = _repository(directory, 'complete.db', media);
      final savedId = await repository.saveCompleteConsultation(
        draft: const ConsultationDraft(
          description: 'Corte',
          helpRequested: false,
        ),
        patient: null,
        guidance: _ready,
        ownerKey: 'guest',
      );
      final saved = (await repository.get(savedId, ownerKey: 'guest'))!;
      repository.failNextCompleteSave = () async => throw StateError('corte');
      await expectLater(
        repository.saveCompleteConsultation(
          draft: const ConsultationDraft(
            description: 'Otra',
            helpRequested: false,
          ),
          patient: null,
          guidance: _ready,
          ownerKey: 'guest',
        ),
        throwsA(isA<StateError>()),
      );
      await repository.close();

      final reopened = _repository(directory, 'complete.db', media);
      final rows = await reopened.list(ownerKey: 'guest');
      final finalized = rows.where(
        (row) => row.syncStatus == 'pending' && row.guidance?.isReady == true,
      );
      expect(finalized, hasLength(1));
      expect(finalized.single.id, savedId);
      expect(finalized.single.mobileConsultationId, saved.mobileConsultationId);
      expect(finalized.single.idempotencyKey, saved.idempotencyKey);
    },
  );

  test('a failed photo save does not keep a path to a missing file', () async {
    final media = Directory(path.join(directory.path, 'media'));
    await media.create();
    final source = File(path.join(directory.path, 'foto.jpg'));
    await source.writeAsBytes([1, 2, 3, 4]);
    final repository = _repository(directory, 'photo.db', media);
    repository.failNextCompleteSave = () async => throw StateError('corte');

    await expectLater(
      repository.saveCompleteConsultation(
        draft: ConsultationDraft(
          description: 'Corte',
          helpRequested: true,
          photoPath: source.path,
        ),
        patient: null,
        guidance: _ready,
        ownerKey: 'guest',
      ),
      throwsA(isA<StateError>()),
    );
    await repository.close();

    final reopened = _repository(directory, 'photo.db', media);
    final rows = await reopened.list(ownerKey: 'guest');
    expect(rows.where((row) => row.syncStatus == 'pending'), isEmpty);
    for (final row in rows) {
      final photo = row.draft.photoPath;
      if (photo != null) expect(File(photo).existsSync(), isTrue);
    }
    expect(
      media.listSync().whereType<File>().map(
        (file) => path.basename(file.path),
      ),
      isEmpty,
    );
    expect(source.existsSync(), isTrue);
  });

  test(
    'a confirmed photo stays and an orphan temporary file is removed on open',
    () async {
      final media = Directory(path.join(directory.path, 'media'));
      await media.create();
      final source = File(path.join(directory.path, 'foto.jpg'));
      await source.writeAsBytes([9, 8, 7]);
      final repository = _repository(directory, 'keep.db', media);
      final id = await repository.saveCompleteConsultation(
        draft: ConsultationDraft(
          description: 'Corte',
          helpRequested: true,
          photoPath: source.path,
        ),
        patient: null,
        guidance: _ready,
        ownerKey: 'guest',
      );
      final saved = (await repository.get(id, ownerKey: 'guest'))!;
      final photo = saved.draft.photoPath!;
      expect(File(photo).existsSync(), isTrue);
      await repository.updateDelivery(
        id,
        ownerKey: 'guest',
        syncStatus: 'confirmed',
        backendConsultationId: 'backend-1',
      );
      await File(path.join(media.path, 'tmp_huerfano.jpg')).writeAsBytes([0]);
      await repository.close();

      final reopened = _repository(directory, 'keep.db', media);
      final row = (await reopened.get(id, ownerKey: 'guest'))!;
      expect(row.syncStatus, 'confirmed');
      expect(row.mobileConsultationId, saved.mobileConsultationId);
      expect(row.idempotencyKey, saved.idempotencyKey);
      expect(row.draft.photoPath, photo);
      expect(File(photo).existsSync(), isTrue);
      expect(
        File(path.join(media.path, 'tmp_huerfano.jpg')).existsSync(),
        isFalse,
      );
    },
  );
}

const _ready = ConsultationGuidance(
  status: GuidanceStatus.ready,
  message: 'Lavar la herida',
);

LocalConsultationRepository _repository(
  Directory directory,
  String name, [
  Directory? media,
]) {
  final repository = LocalConsultationRepository(
    factory: databaseFactoryFfi,
    databasePath: path.join(directory.path, name),
    mediaDirectory: media == null ? null : () async => media.path,
  );
  addTearDown(repository.close);
  return repository;
}
