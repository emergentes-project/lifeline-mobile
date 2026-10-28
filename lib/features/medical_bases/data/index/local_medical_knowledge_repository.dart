import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

class MedicalSource {
  const MedicalSource({
    required this.id,
    required this.institution,
    required this.title,
    required this.url,
    required this.edition,
  });

  final String id;
  final String institution;
  final String title;
  final String url;
  final String? edition;

  factory MedicalSource.fromJson(Map<String, dynamic> json) => MedicalSource(
    id: json['id'] as String,
    institution: json['institution'] as String,
    title: json['title'] as String,
    url: json['url'] as String,
    edition: json['edition'] as String?,
  );
}

class MedicalChunk {
  const MedicalChunk({
    required this.id,
    required this.cardId,
    required this.cardNumber,
    required this.cardTitle,
    required this.section,
    required this.kind,
    required this.ordinal,
    required this.text,
    required this.sourceIds,
  });

  final String id;
  final String cardId;
  final int cardNumber;
  final String cardTitle;
  final String section;
  final String kind;
  final int ordinal;
  final String text;
  final List<String> sourceIds;

  factory MedicalChunk.fromJson(Map<String, dynamic> json) => MedicalChunk(
    id: json['id'] as String,
    cardId: json['card_id'] as String,
    cardNumber: json['card_number'] as int,
    cardTitle: json['card_title'] as String,
    section: json['section'] as String,
    kind: json['kind'] as String,
    ordinal: json['ordinal'] as int,
    text: json['text'] as String,
    sourceIds: (json['source_ids'] as List<dynamic>).cast<String>(),
  );
}

class MedicalSearchResult {
  const MedicalSearchResult({
    required this.cardId,
    required this.cardTitle,
    required this.score,
    required this.chunks,
    required this.sources,
  });

  final String cardId;
  final String cardTitle;
  final double score;
  final List<MedicalChunk> chunks;
  final List<MedicalSource> sources;
}

class LocalMedicalKnowledgeRepository {
  LocalMedicalKnowledgeRepository({
    AssetBundle? bundle,
    DatabaseFactory? factory,
    String? databasePath,
  }) : _bundle = bundle ?? rootBundle,
       _databaseFactory = factory ?? databaseFactory,
       _databasePath = databasePath;

  static const packagePath = 'assets/medical_bases/packages/post_sismo_1_0_0';

  final AssetBundle _bundle;
  final DatabaseFactory _databaseFactory;
  final String? _databasePath;
  Database? _database;
  _LoadedPackage? _active;

  String? get activeVersion => _active?.version;
  String? get commonSafetyRule => _active?.commonSafetyRule;

  Future<void> load() async {
    final files = await Future.wait([
      _bundle.loadString('$packagePath/manifest.json'),
      _bundle.loadString('$packagePath/sources.json'),
      _bundle.loadString('$packagePath/chunks.json'),
      _bundle.loadString('$packagePath/index.json'),
    ]);
    final manifest = (jsonDecode(files[0]) as Map<String, dynamic>);
    final sourceJson = (jsonDecode(files[1]) as List<dynamic>);
    final chunkJson = (jsonDecode(files[2]) as List<dynamic>);
    final index = (jsonDecode(files[3]) as Map<String, dynamic>);
    final sources = sourceJson
        .map((item) => MedicalSource.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
    final chunks = chunkJson
        .map((item) => MedicalChunk.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
    _validate(manifest, index, sources, chunks);
    final database = _database ??= await _databaseFactory.openDatabase(
      _databasePath ??
          path.join(
            await _databaseFactory.getDatabasesPath(),
            'lifeline_medical_bases.db',
          ),
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: _createTables,
      ),
    );
    await _install(database, manifest, index, sources, chunks);
    _active = await _readActive(database);
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
    _active = null;
  }

  static Future<void> _createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE knowledge_packages (
        package_id TEXT NOT NULL,
        version TEXT NOT NULL,
        locale TEXT NOT NULL,
        common_safety_rule TEXT NOT NULL,
        installed_at TEXT NOT NULL,
        active INTEGER NOT NULL CHECK (active IN (0, 1)),
        source_count INTEGER NOT NULL,
        chunk_count INTEGER NOT NULL,
        stop_words_json TEXT NOT NULL,
        average_document_length REAL NOT NULL,
        PRIMARY KEY (package_id, version)
      )
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX one_active_knowledge_package
      ON knowledge_packages(active) WHERE active = 1
    ''');
    await db.execute('''
      CREATE TABLE medical_sources (
        package_id TEXT NOT NULL,
        version TEXT NOT NULL,
        id TEXT NOT NULL,
        institution TEXT NOT NULL,
        title TEXT NOT NULL,
        url TEXT NOT NULL,
        edition TEXT,
        PRIMARY KEY (package_id, version, id),
        FOREIGN KEY (package_id, version)
          REFERENCES knowledge_packages(package_id, version) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE medical_chunks (
        package_id TEXT NOT NULL,
        version TEXT NOT NULL,
        id TEXT NOT NULL,
        position INTEGER NOT NULL,
        card_id TEXT NOT NULL,
        card_number INTEGER NOT NULL,
        card_title TEXT NOT NULL,
        section TEXT NOT NULL,
        kind TEXT NOT NULL,
        ordinal INTEGER NOT NULL,
        text TEXT NOT NULL,
        source_ids_json TEXT NOT NULL,
        document_length INTEGER NOT NULL,
        PRIMARY KEY (package_id, version, id),
        UNIQUE (package_id, version, position),
        FOREIGN KEY (package_id, version)
          REFERENCES knowledge_packages(package_id, version) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE medical_postings (
        package_id TEXT NOT NULL,
        version TEXT NOT NULL,
        term TEXT NOT NULL,
        chunk_position INTEGER NOT NULL,
        frequency INTEGER NOT NULL,
        PRIMARY KEY (package_id, version, term, chunk_position),
        FOREIGN KEY (package_id, version, chunk_position)
          REFERENCES medical_chunks(package_id, version, position) ON DELETE CASCADE
      )
    ''');
  }

  static Future<void> _install(
    Database database,
    Map<String, dynamic> manifest,
    Map<String, dynamic> index,
    List<MedicalSource> sources,
    List<MedicalChunk> chunks,
  ) async {
    final packageId = manifest['package_id'] as String;
    final version = manifest['version'] as String;
    await database.transaction((txn) async {
      final existing = await txn.query(
        'knowledge_packages',
        columns: ['source_count', 'chunk_count'],
        where: 'package_id = ? AND version = ?',
        whereArgs: [packageId, version],
        limit: 1,
      );
      var needsInstall = existing.isEmpty;
      if (existing.isNotEmpty &&
          (existing.first['source_count'] != sources.length ||
              existing.first['chunk_count'] != chunks.length)) {
        await txn.delete(
          'knowledge_packages',
          where: 'package_id = ? AND version = ?',
          whereArgs: [packageId, version],
        );
        needsInstall = true;
      }
      if (needsInstall) {
        final batch = txn.batch();
        batch.insert('knowledge_packages', {
          'package_id': packageId,
          'version': version,
          'locale': manifest['locale'],
          'common_safety_rule': manifest['common_safety_rule'],
          'installed_at': DateTime.now().toUtc().toIso8601String(),
          'active': 0,
          'source_count': sources.length,
          'chunk_count': chunks.length,
          'stop_words_json': jsonEncode(index['stop_words']),
          'average_document_length': index['average_document_length'],
        });
        for (final source in sources) {
          batch.insert('medical_sources', {
            'package_id': packageId,
            'version': version,
            'id': source.id,
            'institution': source.institution,
            'title': source.title,
            'url': source.url,
            'edition': source.edition,
          });
        }
        final lengths = (index['document_lengths'] as List<dynamic>)
            .cast<int>();
        for (var position = 0; position < chunks.length; position++) {
          final chunk = chunks[position];
          batch.insert('medical_chunks', {
            'package_id': packageId,
            'version': version,
            'id': chunk.id,
            'position': position,
            'card_id': chunk.cardId,
            'card_number': chunk.cardNumber,
            'card_title': chunk.cardTitle,
            'section': chunk.section,
            'kind': chunk.kind,
            'ordinal': chunk.ordinal,
            'text': chunk.text,
            'source_ids_json': jsonEncode(chunk.sourceIds),
            'document_length': lengths[position],
          });
        }
        for (final entry
            in (index['postings'] as Map<String, dynamic>).entries) {
          for (final dynamic posting in entry.value as List<dynamic>) {
            final pair = posting as List<dynamic>;
            batch.insert('medical_postings', {
              'package_id': packageId,
              'version': version,
              'term': entry.key,
              'chunk_position': pair[0],
              'frequency': pair[1],
            });
          }
        }
        await batch.commit(noResult: true);
      }
      await txn.update('knowledge_packages', {
        'active': 0,
      }, where: 'active = 1');
      await txn.update(
        'knowledge_packages',
        {'active': 1},
        where: 'package_id = ? AND version = ?',
        whereArgs: [packageId, version],
      );
    });
  }

  static Future<_LoadedPackage> _readActive(Database database) async {
    final packages = await database.query(
      'knowledge_packages',
      where: 'active = 1',
      limit: 1,
    );
    if (packages.length != 1) {
      throw const FormatException('No hay un paquete médico activo');
    }
    final package = packages.single;
    final packageId = package['package_id'] as String;
    final version = package['version'] as String;
    const where = 'package_id = ? AND version = ?';
    final args = [packageId, version];
    final sourceRows = await database.query(
      'medical_sources',
      where: where,
      whereArgs: args,
    );
    final chunkRows = await database.query(
      'medical_chunks',
      where: where,
      whereArgs: args,
      orderBy: 'position ASC',
    );
    final postingRows = await database.query(
      'medical_postings',
      where: where,
      whereArgs: args,
    );
    if (sourceRows.length != package['source_count'] ||
        chunkRows.length != package['chunk_count']) {
      throw const FormatException('Paquete médico incompleto en SQLite');
    }
    final sources = sourceRows
        .map((row) {
          return MedicalSource.fromJson(Map<String, dynamic>.from(row));
        })
        .toList(growable: false);
    final chunks = chunkRows
        .map((row) {
          return MedicalChunk.fromJson({
            ...row,
            'source_ids': jsonDecode(row['source_ids_json'] as String),
          });
        })
        .toList(growable: false);
    final sourceIds = sources.map((source) => source.id).toSet();
    if (chunks.any(
      (chunk) => chunk.sourceIds.any((id) => !sourceIds.contains(id)),
    )) {
      throw const FormatException('Fuentes médicas incompletas en SQLite');
    }
    final postings = <String, List<List<int>>>{};
    for (final row in postingRows) {
      final term = row['term'] as String;
      (postings[term] ??= []).add([
        row['chunk_position'] as int,
        row['frequency'] as int,
      ]);
    }
    return _LoadedPackage(
      version: version,
      commonSafetyRule: package['common_safety_rule'] as String,
      sources: {for (final source in sources) source.id: source},
      chunks: chunks,
      stopWords:
          (jsonDecode(package['stop_words_json'] as String) as List<dynamic>)
              .cast<String>()
              .toSet(),
      lengths: chunkRows
          .map((row) => row['document_length'] as int)
          .toList(growable: false),
      averageLength: (package['average_document_length'] as num).toDouble(),
      postings: postings,
    );
  }

  List<MedicalSearchResult> search(String query, {int limit = 3}) {
    final package = _active;
    if (package == null) throw StateError('El paquete médico no está cargado');
    if (limit < 1) return const [];
    final queryTerms = _terms(query, package.stopWords).toSet();
    if (queryTerms.isEmpty) return const [];
    final scores = <int, double>{};
    final count = package.chunks.length;
    for (final term in queryTerms) {
      final posting = package.postings[term];
      if (posting == null) continue;
      final inverseFrequency = log(
        1 + (count - posting.length + 0.5) / (posting.length + 0.5),
      );
      for (final entry in posting) {
        final index = entry[0];
        final frequency = entry[1];
        final normalizedLength = package.lengths[index] / package.averageLength;
        final weight =
            frequency *
            2.2 /
            (frequency + 1.2 * (0.25 + 0.75 * normalizedLength));
        scores.update(
          index,
          (value) => value + inverseFrequency * weight,
          ifAbsent: () => inverseFrequency * weight,
        );
      }
    }
    final cardScores = <String, double>{};
    for (final entry in scores.entries) {
      final cardId = package.chunks[entry.key].cardId;
      if (entry.value > (cardScores[cardId] ?? 0)) {
        cardScores[cardId] = entry.value;
      }
    }
    final ranked = cardScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ranked
        .take(limit)
        .map((entry) {
          final cardChunks = package.chunks
              .where((chunk) => chunk.cardId == entry.key)
              .toList(growable: false);
          final sourceIds = cardChunks.first.sourceIds;
          return MedicalSearchResult(
            cardId: entry.key,
            cardTitle: cardChunks.first.cardTitle,
            score: entry.value,
            chunks: cardChunks,
            sources: sourceIds
                .map((id) => package.sources[id]!)
                .toList(growable: false),
          );
        })
        .toList(growable: false);
  }

  static List<String> _terms(String text, Set<String> stopWords) {
    var normalized = text.toLowerCase();
    const replacements = {
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ü': 'u',
      'ñ': 'n',
    };
    for (final entry in replacements.entries) {
      normalized = normalized.replaceAll(entry.key, entry.value);
    }
    return RegExp(r'[a-z0-9]+')
        .allMatches(normalized)
        .map((match) => match.group(0)!)
        .where((term) => term.length >= 3 && !stopWords.contains(term))
        .toList(growable: false);
  }

  static void _validate(
    Map<String, dynamic> manifest,
    Map<String, dynamic> index,
    List<MedicalSource> sources,
    List<MedicalChunk> chunks,
  ) {
    if (manifest['schema_version'] != 1 ||
        index['schema_version'] != 1 ||
        manifest['package_id'] != index['package_id'] ||
        manifest['version'] != index['version'] ||
        manifest['source_count'] != sources.length ||
        manifest['chunk_count'] != chunks.length ||
        manifest['card_count'] !=
            chunks.map((chunk) => chunk.cardId).toSet().length ||
        index['normalization'] !=
            'lowercase_unicode_nfkd_ascii_words_min3_stopwords_v1') {
      throw const FormatException('Paquete médico incompatible o incompleto');
    }
    final sourceIds = sources.map((source) => source.id).toSet();
    final chunkIds = chunks.map((chunk) => chunk.id).toSet();
    final lengths = (index['document_lengths'] as List<dynamic>);
    final postings = index['postings'] as Map<String, dynamic>;
    if (sourceIds.length != sources.length ||
        chunkIds.length != chunks.length ||
        lengths.length != chunks.length ||
        (index['average_document_length'] as num) <= 0 ||
        chunks.any(
          (chunk) =>
              chunk.text.trim().isEmpty ||
              chunk.sourceIds.isEmpty ||
              chunk.sourceIds.any((id) => !sourceIds.contains(id)),
        )) {
      throw const FormatException('Referencias o índice médico inválidos');
    }
    for (final cardId in chunks.map((chunk) => chunk.cardId).toSet()) {
      final card = chunks.where((chunk) => chunk.cardId == cardId);
      for (final section in [
        'measures',
        'medical_indications',
        'professional_help',
      ]) {
        if (!card.any(
          (chunk) => chunk.section == section && chunk.kind == 'basic',
        )) {
          throw const FormatException('Falta una pauta básica en el paquete');
        }
      }
    }
    for (final entries in postings.values) {
      for (final dynamic value in entries as List<dynamic>) {
        final entry = value as List<dynamic>;
        if (entry.length != 2 ||
            entry[0] is! int ||
            entry[1] is! int ||
            (entry[0] as int) < 0 ||
            (entry[0] as int) >= chunks.length ||
            (entry[1] as int) < 1) {
          throw const FormatException('Índice médico inválido');
        }
      }
    }
  }
}

class _LoadedPackage {
  const _LoadedPackage({
    required this.version,
    required this.commonSafetyRule,
    required this.sources,
    required this.chunks,
    required this.stopWords,
    required this.lengths,
    required this.averageLength,
    required this.postings,
  });

  final String version;
  final String commonSafetyRule;
  final Map<String, MedicalSource> sources;
  final List<MedicalChunk> chunks;
  final Set<String> stopWords;
  final List<int> lengths;
  final double averageLength;
  final Map<String, List<List<int>>> postings;
}
