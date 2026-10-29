import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../../domain/models/consultation_draft.dart';
import '../../domain/models/consultation_guidance.dart';
import '../../domain/models/patient_draft.dart';

class LocalConsultationRepository {
  LocalConsultationRepository({DatabaseFactory? factory, String? databasePath})
    : _factory = factory ?? databaseFactory,
      _databasePath = databasePath;

  final DatabaseFactory _factory;
  final String? _databasePath;
  Database? _database;

  Future<int> saveDraft(ConsultationDraft draft, PatientDraft patient) async {
    final db = await _open();
    return db.insert('consultations', {
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
      'patient_json': jsonEncode({
        'name': patient.name,
        'age_years': patient.ageYears,
        'province': patient.province,
        'location_description': patient.locationDescription,
        'latitude': patient.latitude,
        'longitude': patient.longitude,
      }),
      'guidance_status': 'pending',
      'preliminary_priority': null,
      'professional_help_recommended': null,
    });
  }

  Future<void> saveGuidance(int id, ConsultationGuidance guidance) async {
    final db = await _open();
    await db.update(
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
          'urgent': guidance.urgent,
          'priority_reason': guidance.priorityReason,
          'professional_help_recommended': guidance.professionalHelpRecommended,
        }),
      },
      where: 'id = ?',
      whereArgs: [id],
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
        version: 3,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE consultations (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
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
        },
      ),
    );
    _database = db;
    return db;
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}
