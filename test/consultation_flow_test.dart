import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lifeline_mobile/features/consultation/data/ai/consultation_guidance_service.dart';
import 'package:lifeline_mobile/features/consultation/data/ai/gemma4_on_device_inference.dart';
import 'package:lifeline_mobile/features/consultation/data/local/local_consultation_repository.dart';
import 'package:lifeline_mobile/features/consultation/domain/models/consultation_draft.dart';
import 'package:lifeline_mobile/features/consultation/domain/models/consultation_guidance.dart';
import 'package:lifeline_mobile/features/consultation/domain/models/patient_draft.dart';
import 'package:lifeline_mobile/features/consultation/domain/models/saved_consultation.dart';
import 'package:lifeline_mobile/features/consultation/presentation/consultation_history_page.dart';
import 'package:lifeline_mobile/features/auth/presentation/blocs/auth_cubit.dart';
import 'package:lifeline_mobile/features/auth/domain/repositories/auth_repository.dart';
import 'package:lifeline_mobile/features/auth/domain/models/authenticated_user.dart';
import 'package:lifeline_mobile/features/medical_bases/data/index/local_medical_knowledge_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeInference extends Gemma4OnDeviceInference {
  FakeInference(this.response);
  final String response;
  String? prompt;
  String? receivedImagePath;

  @override
  Future<bool> get isInstalled async => true;

  @override
  Future<String> generate(String value, {String? imagePath}) async {
    prompt = value;
    receivedImagePath = imagePath;
    return response;
  }
}

class FakeHistoryRepository extends LocalConsultationRepository {
  FakeHistoryRepository(this.items) : super(factory: databaseFactoryFfi);
  final List<SavedConsultation> items;

  @override
  Future<List<SavedConsultation>> list({
    required String ownerKey,
    LocalMedicalKnowledgeRepository? knowledge,
  }) async => items;
}

class _GuestAuthRepository implements AuthRepository {
  @override
  Future<AuthenticatedUser> signIn(String email, String password) =>
      throw UnimplementedError();
  @override
  Future<AuthenticatedUser> registerCitizen(Map<String, dynamic> data) =>
      throw UnimplementedError();
  @override
  Future<AuthenticatedUser> registerMedicalProfessional(
    Map<String, dynamic> data,
  ) => throw UnimplementedError();
  @override
  Future<AuthenticatedUser?> restoreSession() async => null;
  @override
  Future<bool> unlock(String password) async => false;
  @override
  Future<void> updateSavedUser(AuthenticatedUser user) async {}
  @override
  Future<void> signOut() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory directory;
  late LocalMedicalKnowledgeRepository knowledge;
  const patient = PatientDraft(
    name: 'Ana',
    ageYears: 32,
    province: 'Lima',
    requesterPhone: '999111222',
  );

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
              photoPath: '/private/photo.jpg',
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
      expect(model.receivedImagePath, '/private/photo.jpg');
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
      ownerKey: 'user:alice',
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
      ownerKey: 'user:alice',
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
    expect(
      jsonDecode(rows.single['patient_json'] as String)['requester_phone'],
      '999111222',
    );
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
    await old.insert('consultations', {
      'created_at': DateTime.utc(2026).toIso8601String(),
      'description': 'Registro sin propietario',
      'help_requested': 0,
      'patient_json': jsonEncode({'name': 'Previo', 'age_years': 30}),
      'guidance_status': 'pending',
    });
    await old.close();
    final repository = LocalConsultationRepository(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    addTearDown(repository.close);
    final id = await repository.saveDraft(
      const ConsultationDraft(description: 'Corte', helpRequested: false),
      patient,
      ownerKey: 'user:alice',
    );
    await repository.saveGuidance(
      id,
      const ConsultationGuidance(
        status: GuidanceStatus.ready,
        message: 'Orientación local',
        preliminaryPriority: PreliminaryPriority.medium,
        professionalHelpRecommended: true,
      ),
      ownerKey: 'user:alice',
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
    expect(await repository.list(ownerKey: 'user:alice'), hasLength(1));
    expect(await repository.list(ownerKey: 'guest'), isEmpty);
    await upgraded.close();
  });

  test(
    'history restores pending and completed consultations in recent order',
    () async {
      final repository = LocalConsultationRepository(
        factory: databaseFactoryFfi,
        databasePath: '${directory.path}/history.db',
      );
      addTearDown(repository.close);
      final firstId = await repository.saveDraft(
        const ConsultationDraft(
          description: 'Herida superficial',
          helpRequested: false,
          responds: TriageAnswer.yes,
          breathesNormally: TriageAnswer.yes,
          heavyBleeding: TriageAnswer.no,
        ),
        patient,
        ownerKey: 'user:alice',
      );
      final secondId = await repository.saveDraft(
        const ConsultationDraft(
          description: 'Sangrado abundante',
          helpRequested: true,
        ),
        const PatientDraft(name: 'Luis', ageYears: 40),
        ownerKey: 'user:alice',
      );
      final sources = knowledge.search('herida superficial').first.sources;
      await repository.saveGuidance(
        firstId,
        ConsultationGuidance(
          status: GuidanceStatus.ready,
          message: 'Orientación local',
          measures: const ['Lavar la herida'],
          medicalIndications: const ['Cubrir con gasa'],
          professionalHelp: const ['Solicitar valoración si empeora'],
          sources: sources,
          preliminaryPriority: PreliminaryPriority.low,
          professionalHelpRecommended: false,
        ),
        ownerKey: 'user:alice',
      );
      final history = await repository.list(
        ownerKey: 'user:alice',
        knowledge: knowledge,
      );
      expect(history.map((item) => item.id), [secondId, firstId]);
      expect(history.first.guidance, isNull);
      expect(history.first.canRetry, isTrue);
      expect(history.last.guidance!.measures, ['Lavar la herida']);
      expect(history.last.guidance!.sources.first.url, sources.first.url);
      expect(history.last.guidance!.professionalHelpRecommended, isFalse);
      expect(history.last.draft.breathesNormally, TriageAnswer.yes);
      expect(history.last.canRetry, isFalse);
    },
  );

  test('retry updates the same pending consultation row', () async {
    final databasePath = '${directory.path}/retry.db';
    final repository = LocalConsultationRepository(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    addTearDown(repository.close);
    final id = await repository.saveDraft(
      const ConsultationDraft(
        description: 'Corte superficial',
        helpRequested: false,
      ),
      patient,
      ownerKey: 'user:alice',
    );
    final pending = await repository.get(
      id,
      ownerKey: 'user:alice',
      knowledge: knowledge,
    );
    expect(pending?.canRetry, isTrue);
    await repository.saveGuidance(
      id,
      const ConsultationGuidance(
        status: GuidanceStatus.failed,
        message: 'Error del modelo',
      ),
      ownerKey: 'user:alice',
    );
    expect(
      (await repository.get(id, ownerKey: 'user:alice'))?.guidance?.status,
      GuidanceStatus.failed,
    );
    await repository.saveGuidance(
      id,
      const ConsultationGuidance(
        status: GuidanceStatus.ready,
        message: 'Orientación recuperada',
        measures: ['Limpiar el corte'],
      ),
      ownerKey: 'user:alice',
    );
    final restored = await repository.get(id, ownerKey: 'user:alice');
    expect(restored?.guidance?.message, 'Orientación recuperada');
    expect(restored?.canRetry, isFalse);
    final db = await databaseFactoryFfi.openDatabase(databasePath);
    expect(
      (await db.rawQuery(
        'SELECT COUNT(*) AS n FROM consultations',
      )).single['n'],
      1,
    );
    await db.close();
  });

  test(
    'local consultations remain private to their account or guest',
    () async {
      final repository = LocalConsultationRepository(
        factory: databaseFactoryFfi,
        databasePath: '${directory.path}/owners.db',
      );
      addTearDown(repository.close);
      final alice = await repository.saveDraft(
        const ConsultationDraft(description: 'Alice', helpRequested: false),
        patient,
        ownerKey: 'user:alice',
      );
      final guest = await repository.saveDraft(
        const ConsultationDraft(description: 'Invitado', helpRequested: false),
        patient,
        ownerKey: 'guest',
      );
      expect((await repository.list(ownerKey: 'user:alice')).map((e) => e.id), [
        alice,
      ]);
      expect((await repository.list(ownerKey: 'guest')).map((e) => e.id), [
        guest,
      ]);
      expect(await repository.get(alice, ownerKey: 'user:bob'), isNull);
      await expectLater(
        repository.saveGuidance(
          alice,
          const ConsultationGuidance(
            status: GuidanceStatus.failed,
            message: 'X',
          ),
          ownerKey: 'user:bob',
        ),
        throwsStateError,
      );
      expect(
        (await repository.get(alice, ownerKey: 'user:alice'))?.guidance,
        isNull,
      );
    },
  );

  testWidgets('history opens saved answer and offers retry for pending item', (
    tester,
  ) async {
    final repository = FakeHistoryRepository([
      SavedConsultation(
        id: 2,
        createdAt: DateTime.utc(2026, 10, 28),
        draft: const ConsultationDraft(
          description: 'Sangrado',
          helpRequested: true,
        ),
        patient: const PatientDraft(name: 'Luis', ageYears: 40),
        guidance: null,
      ),
      SavedConsultation(
        id: 1,
        createdAt: DateTime.utc(2026, 10, 27),
        draft: const ConsultationDraft(
          description: 'Corte leve',
          helpRequested: false,
        ),
        patient: patient,
        guidance: const ConsultationGuidance(
          status: GuidanceStatus.ready,
          message: 'Respuesta guardada',
          measures: ['Lavar la herida'],
        ),
      ),
    ]);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<LocalConsultationRepository>.value(
            value: repository,
          ),
          RepositoryProvider<LocalMedicalKnowledgeRepository>.value(
            value: knowledge,
          ),
          RepositoryProvider<Gemma4OnDeviceInference>.value(
            value: FakeInference('{"cards":[],"conditions":[]}'),
          ),
        ],
        child: BlocProvider(
          create: (_) => AuthCubit(_GuestAuthRepository())..continueAsGuest(),
          child: const MaterialApp(home: ConsultationHistoryPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Luis'), findsOneWidget);
    expect(find.text('Ana'), findsOneWidget);
    await tester.tap(find.text('Luis'));
    await tester.pumpAndSettle();
    expect(find.text('Reintentar orientación'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ana'));
    await tester.pumpAndSettle();
    expect(find.text('Respuesta guardada'), findsOneWidget);
    expect(find.text('1. Lavar la herida'), findsOneWidget);
    expect(find.text('Reintentar orientación'), findsNothing);
  });
}
