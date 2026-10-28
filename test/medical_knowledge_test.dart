import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeline_mobile/features/medical_bases/data/index/local_medical_knowledge_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'the bundled package persists in SQLite and returns a complete card',
    () async {
      sqfliteFfiInit();
      final directory = await Directory.systemTemp.createTemp(
        'lifeline_knowledge_',
      );
      final databasePath = '${directory.path}/medical.db';
      final repository = LocalMedicalKnowledgeRepository(
        factory: databaseFactoryFfi,
        databasePath: databasePath,
      );
      addTearDown(() async {
        await repository.close();
        await directory.delete(recursive: true);
      });
      await repository.load();

      expect(repository.activeVersion, '1.0.0');
      expect(repository.commonSafetyRule, isNotEmpty);
      final results = repository.search(
        'sangrado abundante por nariz después de golpe',
      );
      expect(results, isNotEmpty);
      expect(results.first.cardId, 'post_sismo_13');
      expect(results.first.sources, isNotEmpty);
      expect(
        results.first.chunks.any(
          (chunk) => chunk.section == 'measures' && chunk.kind == 'basic',
        ),
        isTrue,
      );
      expect(
        results.first.chunks.any(
          (chunk) =>
              chunk.section == 'medical_indications' && chunk.kind == 'basic',
        ),
        isTrue,
      );
      expect(
        results.first.chunks.any(
          (chunk) => chunk.section == 'professional_help',
        ),
        isTrue,
      );
      await repository.close();

      final database = await databaseFactoryFfi.openDatabase(databasePath);
      expect(
        (await database.rawQuery(
          'SELECT COUNT(*) AS n FROM knowledge_packages WHERE active = 1',
        )).single['n'],
        1,
      );
      expect(
        (await database.rawQuery(
          'SELECT COUNT(*) AS n FROM medical_sources',
        )).single['n'],
        31,
      );
      expect(
        (await database.rawQuery(
          'SELECT COUNT(*) AS n FROM medical_chunks',
        )).single['n'],
        118,
      );
      expect(
        (await database.rawQuery(
              'SELECT COUNT(*) AS n FROM medical_postings',
            )).single['n']
            as int,
        greaterThan(118),
      );
      await database.close();

      await repository.load();
      expect(
        repository.search('sangrado abundante por nariz').first.cardId,
        'post_sismo_13',
      );
    },
  );
}
