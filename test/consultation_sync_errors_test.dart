import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifeline_mobile/features/consultation/application/consultation_sync_service.dart';
import 'package:lifeline_mobile/features/consultation/data/local/local_consultation_repository.dart';
import 'package:lifeline_mobile/features/consultation/domain/models/consultation_draft.dart';
import 'package:lifeline_mobile/features/consultation/domain/models/consultation_guidance.dart';
import 'package:lifeline_mobile/features/consultation/domain/models/patient_draft.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('lifeline_sync_errors_');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test(
    'timeout, 409 and 500 stay pending and are counted by type and operation',
    () async {
      final repository = LocalConsultationRepository(
        factory: databaseFactoryFfi,
        databasePath: path.join(directory.path, 'errors.db'),
      );
      addTearDown(repository.close);
      final first = await _ready(repository, 'Primera');
      final second = await _ready(repository, 'Segunda');
      final third = await _ready(repository, 'Tercera');
      final calls = <int>[];
      final service = ConsultationSyncService(
        repository: repository,
        client: MockClient((request) async {
          calls.add(
            request.url.path == '/api/v1/consultation-submissions' ? 1 : 0,
          );
          final sent = jsonDecode(request.body) as Map<String, dynamic>;
          if (sent['mobileConsultationId'] == third.mobileConsultationId) {
            throw TimeoutException('agotado');
          }
          if (sent['mobileConsultationId'] == second.mobileConsultationId) {
            return http.Response(jsonEncode({'message': 'conflicto'}), 409);
          }
          return http.Response('', 500);
        }),
      );

      final attempts = await service.syncPending(ownerKey: 'guest');

      expect(calls, [1, 1, 1]);
      expect(attempts.map((item) => item.syncStatus), everyElement('pending'));
      for (final row in [first, second, third]) {
        final stored = await repository.get(row.id, ownerKey: 'guest');
        expect(stored?.syncStatus, 'pending');
        expect(stored?.mobileConsultationId, row.mobileConsultationId);
        expect(stored?.idempotencyKey, row.idempotencyKey);
      }
      final failures = await repository.syncFailures(ownerKey: 'guest');
      expect(failures, hasLength(3));
      expect(
        failures.map((item) => item.operation),
        everyElement('post_consultation'),
      );
      expect(failures.map((item) => item.type).toSet(), {
        'timeout',
        'http_409',
        'http_5xx',
      });
      expect(
        failures.singleWhere((item) => item.type == 'http_409').httpStatus,
        409,
      );
      expect(
        failures.singleWhere((item) => item.type == 'http_5xx').httpStatus,
        500,
      );
      expect(
        failures.singleWhere((item) => item.type == 'timeout').httpStatus,
        isNull,
      );
      for (final failure in failures) {
        expect(failure.message.contains('999000111'), isFalse);
        expect(failure.message.contains('Lavar la herida'), isFalse);
        expect(failure.message.contains('secreto'), isFalse);
      }
      final counts = await repository.syncFailureCounts(ownerKey: 'guest');
      expect(counts, hasLength(3));
      expect(
        counts.map((item) => '${item.type}:${item.operation}:${item.count}'),
        [
          'http_409:post_consultation:1',
          'http_5xx:post_consultation:1',
          'timeout:post_consultation:1',
        ],
      );
      final other = await repository.syncFailureCounts(ownerKey: 'user:otra');
      expect(other, isEmpty);
    },
  );
}

Future<SavedConsultationRecord> _ready(
  LocalConsultationRepository repository,
  String description,
) async {
  final id = await repository.saveDraft(
    ConsultationDraft(description: description, helpRequested: true),
    const PatientDraft(name: 'Ana', ageYears: 32, requesterPhone: '999000111'),
    ownerKey: 'guest',
  );
  await repository.saveGuidance(
    id,
    const ConsultationGuidance(
      status: GuidanceStatus.ready,
      message: 'Lavar la herida secreta',
    ),
    ownerKey: 'guest',
  );
  final row = (await repository.get(id, ownerKey: 'guest'))!;
  return SavedConsultationRecord(
    id: row.id,
    mobileConsultationId: row.mobileConsultationId,
    idempotencyKey: row.idempotencyKey,
  );
}

class SavedConsultationRecord {
  const SavedConsultationRecord({
    required this.id,
    required this.mobileConsultationId,
    required this.idempotencyKey,
  });

  final int id;
  final String mobileConsultationId;
  final String idempotencyKey;
}
