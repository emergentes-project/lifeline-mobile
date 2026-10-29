import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../../domain/models/consultation_draft.dart';
import '../../domain/models/consultation_guidance.dart';
import '../../domain/models/patient_draft.dart';
import '../../domain/models/saved_consultation.dart';
import '../../../medical_bases/data/index/local_medical_knowledge_repository.dart';

class LocalConsultationRepository {
  LocalConsultationRepository({DatabaseFactory? factory, String? databasePath})
    : _factory = factory ?? databaseFactory,
      _databasePath = databasePath;

  final DatabaseFactory _factory;
  final String? _databasePath;
  Database? _database;

  Future<int> saveDraft(
    ConsultationDraft draft,
    PatientDraft? patient, {
    required String ownerKey,
  }) async {
    final db = await _open();
    return db.insert('consultations', {
      'owner_key': ownerKey,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'description': draft.description.trim(),
      'help_requested': draft.helpRequested ? 1 : 0,
      'photo_path': draft.photoPath,
      'audio_path': draft.audioPath,
      'triage_json': jsonEncode({
        'responds': draft.responds.name,
        'breathes_normally': draft.breathesNormally.name,
        'heavy_bleeding': draft.heavyBleeding.name,
      }),
      'patient_json': jsonEncode(
        patient == null
            ? null
            : {
                'name': patient.name,
                'age_years': patient.ageYears,
                'province': patient.province,
                'location_description': patient.locationDescription,
                'latitude': patient.latitude,
                'longitude': patient.longitude,
                'requester_phone': patient.requesterPhone,
              },
      ),
      'guidance_status': 'pending',
      'preliminary_priority': null,
      'professional_help_recommended': null,
    });
  }

  Future<void> saveGuidance(
    int id,
    ConsultationGuidance guidance, {
    required String ownerKey,
  }) async {
    final db = await _open();
    final updated = await db.update(
      'consultations',
      {
        'guidance_status': guidance.status.name,
        'preliminary_priority': guidance.preliminaryPriority?.name
            .toUpperCase(),
        'professional_help_recommended':
            guidance.professionalHelpRecommended == null
            ? null
            : guidance.professionalHelpRecommended!
            ? 1
            : 0,
        'guidance_json': jsonEncode({
          'message': guidance.message,
          'measures': guidance.measures,
          'medical_indications': guidance.medicalIndications,
          'professional_help': guidance.professionalHelp,
          'card_titles': guidance.cardTitles,
          'chunk_ids': guidance.chunkIds,
          'source_ids': guidance.sources.map((source) => source.id).toList(),
          'sources': [
            for (final source in guidance.sources)
              {
                'id': source.id,
                'institution': source.institution,
                'title': source.title,
                'url': source.url,
                'edition': source.edition,
              },
          ],
          'urgent': guidance.urgent,
          'priority_reason': guidance.priorityReason,
          'professional_help_recommended': guidance.professionalHelpRecommended,
        }),
      },
      where: 'id = ? AND owner_key = ?',
      whereArgs: [id, ownerKey],
    );
    if (updated == 0) {
      throw StateError('Consulta no disponible para este usuario.');
    }
  }

  Future<List<SavedConsultation>> list({
    required String ownerKey,
    LocalMedicalKnowledgeRepository? knowledge,
  }) async {
    final db = await _open();
    final rows = await db.query(
      'consultations',
      where: 'owner_key = ?',
      whereArgs: [ownerKey],
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map((row) => _read(row, knowledge)).toList(growable: false);
  }

  Future<SavedConsultation?> get(
    int id, {
    required String ownerKey,
    LocalMedicalKnowledgeRepository? knowledge,
  }) async {
    final db = await _open();
    final rows = await db.query(
      'consultations',
      where: 'id = ? AND owner_key = ?',
      whereArgs: [id, ownerKey],
      limit: 1,
    );
    return rows.isEmpty ? null : _read(rows.single, knowledge);
  }

  SavedConsultation _read(
    Map<String, Object?> row,
    LocalMedicalKnowledgeRepository? knowledge,
  ) {
    final patientJson =
        jsonDecode(row['patient_json'] as String) as Map<String, dynamic>?;
    final triageJson = row['triage_json'] == null
        ? <String, dynamic>{}
        : jsonDecode(row['triage_json'] as String) as Map<String, dynamic>;
    final guidanceJson = row['guidance_json'] == null
        ? null
        : jsonDecode(row['guidance_json'] as String) as Map<String, dynamic>;
    TriageAnswer answer(Object? value) =>
        TriageAnswer.values.where((item) => item.name == value).firstOrNull ??
        TriageAnswer.unknown;
    final status =
        GuidanceStatus.values
            .where((item) => item.name == row['guidance_status'])
            .firstOrNull ??
        GuidanceStatus.failed;
    final priority = PreliminaryPriority.values
        .where((item) => item.name.toUpperCase() == row['preliminary_priority'])
        .firstOrNull;
    final savedSourceIds =
        (guidanceJson?['source_ids'] as List<dynamic>? ?? const [])
            .whereType<String>();
    final sourceSnapshots =
        (guidanceJson?['sources'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(MedicalSource.fromJson)
            .toList(growable: false);
    final sources = sourceSnapshots.isNotEmpty
        ? sourceSnapshots
        : knowledge?.sourcesForIds(savedSourceIds) ?? <MedicalSource>[];
    List<String> strings(String key) =>
        (guidanceJson?[key] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(growable: false);
    final helpValue = row['professional_help_recommended'];
    return SavedConsultation(
      id: row['id'] as int,
      createdAt: DateTime.parse(row['created_at'] as String),
      draft: ConsultationDraft(
        description: row['description'] as String,
        helpRequested: row['help_requested'] == 1,
        photoPath: row['photo_path'] as String?,
        audioPath: row['audio_path'] as String?,
        responds: answer(triageJson['responds']),
        breathesNormally: answer(triageJson['breathes_normally']),
        heavyBleeding: answer(triageJson['heavy_bleeding']),
      ),
      patient: patientJson == null
          ? null
          : PatientDraft(
              name: patientJson['name'] as String,
              ageYears: patientJson['age_years'] as int,
              province: patientJson['province'] as String?,
              locationDescription:
                  patientJson['location_description'] as String?,
              latitude: (patientJson['latitude'] as num?)?.toDouble(),
              longitude: (patientJson['longitude'] as num?)?.toDouble(),
              requesterPhone: patientJson['requester_phone'] as String?,
            ),
      guidance: status == GuidanceStatus.ready || guidanceJson != null
          ? ConsultationGuidance(
              status: status,
              message:
                  guidanceJson?['message'] as String? ??
                  'La orientación quedó pendiente.',
              measures: strings('measures'),
              medicalIndications: strings('medical_indications'),
              professionalHelp: strings('professional_help'),
              sources: sources,
              cardTitles: strings('card_titles'),
              chunkIds: strings('chunk_ids'),
              urgent: guidanceJson?['urgent'] == true,
              preliminaryPriority: priority,
              priorityReason: guidanceJson?['priority_reason'] as String?,
              professionalHelpRecommended: helpValue == null
                  ? null
                  : helpValue == 1,
            )
          : null,
    );
  }

  Future<Database> _open() async {
    if (_database != null) return _database!;
    final db = await _factory.openDatabase(
      _databasePath ??
          path.join(
            await _factory.getDatabasesPath(),
            'lifeline_consultations.db',
          ),
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
        onUpgrade: (db, oldVersion, _) async {
          if (oldVersion < 2) {
            await db.execute(
              'ALTER TABLE consultations ADD COLUMN triage_json TEXT',
            );
            await db.execute(
              'ALTER TABLE consultations ADD COLUMN preliminary_priority TEXT',
            );
          }
          if (oldVersion < 3) {
            await db.execute(
              'ALTER TABLE consultations ADD COLUMN professional_help_recommended INTEGER',
            );
          }
          if (oldVersion < 4) {
            await db.execute(
              "ALTER TABLE consultations ADD COLUMN owner_key TEXT NOT NULL DEFAULT 'legacy-unassigned'",
            );
          }
        },
      ),
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS consultations_owner_date_idx ON consultations(owner_key, created_at DESC, id DESC)',
    );
    _database = db;
    return db;
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
