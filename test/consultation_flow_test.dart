import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeline_mobile/features/consultation/data/ai/consultation_guidance_service.dart';
import 'package:lifeline_mobile/features/consultation/data/ai/gemma4_on_device_inference.dart';
import 'package:lifeline_mobile/features/consultation/data/local/local_consultation_repository.dart';
import 'package:lifeline_mobile/features/consultation/domain/models/consultation_draft.dart';
import 'package:lifeline_mobile/features/consultation/domain/models/consultation_guidance.dart';
import 'package:lifeline_mobile/features/consultation/domain/models/patient_draft.dart';
import 'package:lifeline_mobile/features/medical_bases/data/index/local_medical_knowledge_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeInference extends Gemma4OnDeviceInference {
  FakeInference(this.response);
  final String response;
  String? prompt;

  @override
  Future<bool> get isInstalled async => true;

  @override
  Future<String> generate(String value, {String? imagePath}) async {
    prompt = value;
    return response;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory directory;
  late LocalMedicalKnowledgeRepository knowledge;
  const patient = PatientDraft(name: 'Ana', ageYears: 32, province: 'Lima');

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('lifeline_flow_');
    knowledge = LocalMedicalKnowledgeRepository(
      factory: databaseFactoryFfi,
      databasePath: '${directory.path}/medical.db',
    );
    await knowledge.load();
  });

  tearDown(() async {
    await knowledge.close();
    await directory.delete(recursive: true);
  });

  test(
    'returns only approved basic text and conditionals with literal evidence',
    () async {
      final model = FakeInference(
        jsonEncode({
          'cards': [
            {
              'card_id': 'post_sismo_13',
              'evidence': 'sangrado abundante por nariz',
            },
            {'card_id': 'post_sismo_01', 'evidence': 'frase inventada'},
            {'card_id': 'post_sismo_04'},
          ],
          'conditions': [
            {
              'chunk_id': 'post_sismo_13_measures_conditional_02',
              'evidence': 'sangrado abundante por nariz',
            },
            {
              'chunk_id': 'post_sismo_13_medical_indications_conditional_03',
              'evidence': 'no respira',
            },
          ],
          'preliminary_priority': 'HIGH',
          'priority_evidence': 'sangrado abundante',
          'invented_advice': 'Toma un medicamento no aprobado',
        }),
      );
      final guidance =
          await ConsultationGuidanceService(
            knowledge: knowledge,
            inference: model,
          ).create(
            draft: const ConsultationDraft(
              description:
                  'Hay sangrado abundante por nariz después de un golpe.',
              helpRequested: true,
              heavyBleeding: TriageAnswer.yes,
            ),
            patient: patient,
          );

      expect(guidance.status, GuidanceStatus.ready);
      expect(guidance.cardTitles, hasLength(1));
      expect(guidance.chunkIds, contains('post_sismo_13_measures_basic'));
      expect(
        guidance.chunkIds,
        contains('post_sismo_13_measures_conditional_02'),
      );
      expect(
        guidance.chunkIds,
        isNot(contains('post_sismo_13_medical_indications_conditional_03')),
      );
      expect(
        guidance.chunkIds,
        isNot(contains('post_sismo_01_measures_basic')),
      );
      expect(
        guidance.measures.join(' '),
        isNot(contains('medicamento no aprobado')),
      );
      expect(guidance.sources, isNotEmpty);
      expect(guidance.preliminaryPriority, PreliminaryPriority.high);
      expect(model.prompt, isNot(contains('Ana')));
      expect(model.prompt, isNot(contains('Lima')));
    },
  );

  test('requires a text description and rejects unsupported selection', () async {
    final model = FakeInference(
      '{"cards":[{"card_id":"post_sismo_13","evidence":"inventado"}],"conditions":[]}',
    );
    final service = ConsultationGuidanceService(
      knowledge: knowledge,
      inference: model,
    );
    expect(
      (await service.create(
        draft: const ConsultationDraft(description: '', helpRequested: false),
        patient: patient,
      )).status,
      GuidanceStatus.needsDescription,
    );
    expect(
      (await service.create(
        draft: const ConsultationDraft(
          description: 'sangrado abundante por nariz',
          helpRequested: false,
        ),
        patient: patient,
      )).status,
      GuidanceStatus.noEvidence,
    );
  });

  test('does not accept LOW when initial checks are unknown', () async {
    final model = FakeInference(
      jsonEncode({
        'cards': [
          {'card_id': 'post_sismo_08', 'evidence': 'corte superficial'},
        ],
        'conditions': [],
        'preliminary_priority': 'LOW',
        'priority_evidence': 'corte superficial',
        'professional_help_recommended': false,
        'help_evidence': 'texto que no aparece en el caso',
      }),
    );
    final guidance =
        await ConsultationGuidanceService(
          knowledge: knowledge,
          inference: model,
        ).create(
          draft: const ConsultationDraft(
            description: 'Tiene un corte superficial.',
            helpRequested: false,
          ),
          patient: patient,
        );
    expect(guidance.status, GuidanceStatus.ready);
    expect(guidance.preliminaryPriority, PreliminaryPriority.medium);
    expect(guidance.professionalHelpRecommended, isNull);
  });

  test('severe initial check overrides a lower model priority', () async {
    final model = FakeInference(
      jsonEncode({
        'cards': [
          {'card_id': 'post_sismo_13', 'evidence': 'sangra por nariz'},
        ],
        'conditions': [],
        'preliminary_priority': 'LOW',
        'priority_evidence': 'sangra por nariz',
        'professional_help_recommended': false,
        'help_evidence': 'sangra por nariz',
      }),
    );
    final guidance =
        await ConsultationGuidanceService(
          knowledge: knowledge,
          inference: model,
        ).create(
          draft: const ConsultationDraft(
            description: 'Sangra por nariz.',
            helpRequested: true,
            responds: TriageAnswer.no,
          ),
          patient: patient,
        );
    expect(guidance.preliminaryPriority, PreliminaryPriority.high);
    expect(guidance.urgent, isTrue);
    expect(guidance.professionalHelpRecommended, isTrue);
  });

  test('accepts model LOW with explicit safe initial checks', () async {
    final model = FakeInference(
      jsonEncode({
        'cards': [
          {'card_id': 'post_sismo_08', 'evidence': 'corte superficial'},
        ],
        'conditions': [],
        'preliminary_priority': 'LOW',
        'priority_evidence': 'corte superficial',
        'professional_help_recommended': false,
        'help_evidence': 'texto que no aparece en el caso',
      }),
    );
    final guidance =
        await ConsultationGuidanceService(
          knowledge: knowledge,
          inference: model,
        ).create(
          draft: const ConsultationDraft(
            description: 'Tiene un corte superficial.',
            helpRequested: false,
            responds: TriageAnswer.yes,
            breathesNormally: TriageAnswer.yes,
            heavyBleeding: TriageAnswer.no,
          ),
          patient: patient,
        );
    expect(guidance.preliminaryPriority, PreliminaryPriority.low);
    expect(guidance.professionalHelpRecommended, isFalse);
  });

  test('persists draft and source references locally', () async {
    final repository = LocalConsultationRepository(
      factory: databaseFactoryFfi,
      databasePath: '${directory.path}/consultations.db',
    );
    addTearDown(repository.close);
    final id = await repository.saveDraft(
      const ConsultationDraft(
        description: 'Herida en la mano',
        helpRequested: true,
      ),
      patient,
    );
    await repository.saveGuidance(
      id,
      const ConsultationGuidance(
        status: GuidanceStatus.noEvidence,
        message: 'Faltan datos',
        preliminaryPriority: PreliminaryPriority.high,
        priorityReason: 'Comprobación inicial grave',
        professionalHelpRecommended: true,
      ),
    );
    final db = await databaseFactoryFfi.openDatabase(
      '${directory.path}/consultations.db',
    );
    final rows = await db.query(
      'consultations',
      where: 'id = ?',
      whereArgs: [id],
    );
    expect(rows, hasLength(1));
    expect(rows.single['help_requested'], 1);
    expect(rows.single['guidance_status'], 'noEvidence');
    expect(rows.single['preliminary_priority'], 'HIGH');
    expect(rows.single['professional_help_recommended'], 1);
    expect(jsonDecode(rows.single['patient_json'] as String)['name'], 'Ana');
    await db.close();
  });

  test('upgrades existing consultation database to store priority', () async {
    final databasePath = '${directory.path}/old_consultations.db';
    final old = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE consultations (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              created_at TEXT NOT NULL,
              description TEXT NOT NULL,
              help_requested INTEGER NOT NULL,
              photo_path TEXT,
              audio_path TEXT,
              patient_json TEXT NOT NULL,
              guidance_status TEXT NOT NULL,
              guidance_json TEXT
            )
          ''');
        },
      ),
    );
    await old.close();
    final repository = LocalConsultationRepository(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    addTearDown(repository.close);
    final id = await repository.saveDraft(
      const ConsultationDraft(description: 'Corte', helpRequested: false),
      patient,
    );
    await repository.saveGuidance(
      id,
      const ConsultationGuidance(
        status: GuidanceStatus.ready,
        message: 'Orientación local',
        preliminaryPriority: PreliminaryPriority.medium,
        professionalHelpRecommended: true,
      ),
    );
    final upgraded = await databaseFactoryFfi.openDatabase(databasePath);
    final rows = await upgraded.query(
      'consultations',
      where: 'id = ?',
      whereArgs: [id],
    );
    expect(rows.single['preliminary_priority'], 'MEDIUM');
    expect(rows.single['professional_help_recommended'], 1);
    expect(rows.single['triage_json'], isNotNull);
    await upgraded.close();
  });
}
