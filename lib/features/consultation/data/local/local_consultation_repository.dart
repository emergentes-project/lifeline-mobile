import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../../domain/models/consultation_draft.dart';
import '../../domain/models/consultation_guidance.dart';
import '../../domain/models/patient_draft.dart';
import '../../domain/models/saved_consultation.dart';
import '../../../medical_bases/data/index/local_medical_knowledge_repository.dart';

final _uuidRandom = Random.secure();

String _uuidV4() {
  final bytes = List<int>.generate(16, (_) => _uuidRandom.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class LocalConsultationRepository {
  LocalConsultationRepository({
    DatabaseFactory? factory,
    String? databasePath,
    this.mediaDirectory,
  }) : _factory = factory ?? databaseFactory,
       _databasePath = databasePath;

  final DatabaseFactory _factory;
  final String? _databasePath;
  final Future<String> Function()? mediaDirectory;
  Database? _database;

  /// Prueba: se ejecuta después de copiar los medios y antes del insert.
  Future<void> Function()? failNextCompleteSave;

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
      'mobile_consultation_id': _uuidV4(),
      'idempotency_key': _uuidV4(),
      'sync_status': 'draft',
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

  Future<int> saveCompleteConsultation({
    required ConsultationDraft draft,
    required PatientDraft? patient,
    required ConsultationGuidance guidance,
    required String ownerKey,
  }) async {
    if (!guidance.isReady) {
      throw StateError('La orientación todavía no está lista.');
    }
    final db = await _open();
    final staged = await _stageMedia(draft);
    try {
      final interrupt = failNextCompleteSave;
      failNextCompleteSave = null;
      if (interrupt != null) await interrupt();
      return await db.insert(
        'consultations',
        _rowValues(
          draft: draft,
          patient: patient,
          ownerKey: ownerKey,
          photoPath: staged.photoPath,
          audioPath: staged.audioPath,
          guidance: guidance,
          syncStatus: 'pending',
        ),
      );
    } catch (_) {
      await _discard(staged.created);
      rethrow;
    }
  }

  Future<void> saveGuidance(
    int id,
    ConsultationGuidance guidance, {
    required String ownerKey,
  }) async {
    final db = await _open();
    final existing = await db.query(
      'consultations',
      columns: ['sync_status'],
      where: 'id = ? AND owner_key = ?',
      whereArgs: [id, ownerKey],
      limit: 1,
    );
    if (existing.isEmpty) {
      throw StateError('Consulta no disponible para este usuario.');
    }
    final current = existing.single['sync_status'] as String?;
    final values = _guidanceValues(guidance);
    if (guidance.isReady && current != 'confirmed') {
      values['sync_status'] = 'pending';
    }
    final updated = await db.update(
      'consultations',
      values,
      where: 'id = ? AND owner_key = ?',
      whereArgs: [id, ownerKey],
    );
    if (updated == 0) {
      throw StateError('Consulta no disponible para este usuario.');
    }
  }

  Future<void> updateDelivery(
    int id, {
    required String ownerKey,
    required String syncStatus,
    String? backendConsultationId,
  }) async {
    final db = await _open();
    final values = <String, Object?>{'sync_status': syncStatus};
    if (backendConsultationId != null && backendConsultationId.isNotEmpty) {
      values['backend_consultation_id'] = backendConsultationId;
    }
    final updated = await db.update(
      'consultations',
      values,
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
      mobileConsultationId: row['mobile_consultation_id'] as String? ?? '',
      idempotencyKey: row['idempotency_key'] as String? ?? '',
      backendConsultationId: row['backend_consultation_id'] as String?,
      syncStatus: row['sync_status'] as String? ?? 'pending',
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
        version: 5,
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
              professional_help_recommended INTEGER,
              mobile_consultation_id TEXT NOT NULL,
              idempotency_key TEXT NOT NULL,
              backend_consultation_id TEXT,
              sync_status TEXT NOT NULL
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
          if (oldVersion < 5) {
            await db.execute(
              'ALTER TABLE consultations ADD COLUMN mobile_consultation_id TEXT',
            );
            await db.execute(
              'ALTER TABLE consultations ADD COLUMN idempotency_key TEXT',
            );
            await db.execute(
              'ALTER TABLE consultations ADD COLUMN backend_consultation_id TEXT',
            );
            await db.execute(
              "ALTER TABLE consultations ADD COLUMN sync_status TEXT NOT NULL DEFAULT 'pending'",
            );
            final rows = await db.query(
              'consultations',
              columns: ['id', 'mobile_consultation_id', 'idempotency_key'],
            );
            for (final row in rows) {
              final mobile = row['mobile_consultation_id'] as String?;
              final key = row['idempotency_key'] as String?;
              if (mobile != null &&
                  mobile.isNotEmpty &&
                  key != null &&
                  key.isNotEmpty) {
                continue;
              }
              await db.update(
                'consultations',
                {
                  'mobile_consultation_id': mobile == null || mobile.isEmpty
                      ? _uuidV4()
                      : mobile,
                  'idempotency_key': key == null || key.isEmpty
                      ? _uuidV4()
                      : key,
                },
                where: 'id = ?',
                whereArgs: [row['id']],
              );
            }
          }
        },
      ),
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS consultations_owner_date_idx ON consultations(owner_key, created_at DESC, id DESC)',
    );
    _database = db;
    await _forgetUnreferencedMedia(db);
    return db;
  }

  Map<String, Object?> _rowValues({
    required ConsultationDraft draft,
    required PatientDraft? patient,
    required String ownerKey,
    required String? photoPath,
    required String? audioPath,
    required ConsultationGuidance? guidance,
    required String syncStatus,
  }) => {
    'owner_key': ownerKey,
    'created_at': DateTime.now().toUtc().toIso8601String(),
    'description': draft.description.trim(),
    'help_requested': draft.helpRequested ? 1 : 0,
    'mobile_consultation_id': _uuidV4(),
    'idempotency_key': _uuidV4(),
    'sync_status': syncStatus,
    'photo_path': photoPath,
    'audio_path': audioPath,
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
    ...(guidance == null
        ? {
            'guidance_status': 'pending',
            'preliminary_priority': null,
            'professional_help_recommended': null,
          }
        : _guidanceValues(guidance)),
  };

  Map<String, Object?> _guidanceValues(ConsultationGuidance guidance) => {
    'guidance_status': guidance.status.name,
    'preliminary_priority': guidance.preliminaryPriority?.name.toUpperCase(),
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
  };

  Future<({String? photoPath, String? audioPath, List<String> created})>
  _stageMedia(ConsultationDraft draft) async {
    final created = <String>[];
    try {
      return (
        photoPath: await _copyMedia(draft.photoPath, created),
        audioPath: await _copyMedia(draft.audioPath, created),
        created: created,
      );
    } catch (_) {
      await _discard(created);
      rethrow;
    }
  }

  Future<String?> _copyMedia(String? source, List<String> created) async {
    if (source == null || source.isEmpty) return null;
    final file = File(source);
    if (!await file.exists()) {
      throw StateError('El archivo de la consulta ya no está.');
    }
    final root = await _mediaRoot() ?? file.parent.path;
    final folder = Directory(root);
    if (!await folder.exists()) await folder.create(recursive: true);
    final extension = path.extension(source);
    final target = path.join(root, 'tmp_${_uuidV4()}$extension');
    final copied = await file.copy(target);
    created.add(copied.path);
    return copied.path;
  }

  Future<void> _discard(List<String> paths) async {
    for (final item in paths) {
      try {
        await File(item).delete();
      } catch (_) {
        // El temporal ya no estaba.
      }
    }
  }

  Future<String?> _mediaRoot() async {
    final resolve = mediaDirectory;
    if (resolve == null) return null;
    try {
      return await resolve();
    } catch (_) {
      return null;
    }
  }

  Future<void> _forgetUnreferencedMedia(Database db) async {
    final root = await _mediaRoot();
    if (root == null) return;
    final folder = Directory(root);
    if (!await folder.exists()) return;
    final rows = await db.query(
      'consultations',
      columns: ['photo_path', 'audio_path'],
    );
    final keep = <String>{};
    for (final row in rows) {
      final photo = row['photo_path'] as String?;
      final audio = row['audio_path'] as String?;
      if (photo != null && photo.isNotEmpty) keep.add(_mediaKey(photo));
      if (audio != null && audio.isNotEmpty) keep.add(_mediaKey(audio));
    }
    await for (final entity in folder.list(followLinks: false)) {
      if (entity is! File) continue;
      if (keep.contains(_mediaKey(entity.path))) continue;
      try {
        await entity.delete();
      } catch (_) {
        // Otro proceso puede estar usando el archivo.
      }
    }
  }

  String _mediaKey(String value) =>
      path.normalize(File(value).absolute.path).toLowerCase();

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
