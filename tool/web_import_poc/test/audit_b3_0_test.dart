import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import '../bin/audit_b3_0.dart' as audit;

void main() {
  test(
    'batch 3 corpus matches visible DOM; every instruction reference resolves',
    () {
      final report =
          jsonDecode(
                File('results/b3_0_source_truth_audit.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      final recipes = (report['recipes'] as List).cast<Map<String, dynamic>>();
      expect(recipes.map((r) => r['id']).toList(), [
        for (var id = 21; id <= 30; id++) '$id',
      ]);
      for (final r in recipes.where(
        (r) => int.parse(r['id'] as String) <= 28,
      )) {
        final id = int.parse(r['id'] as String);
        final source = File(
          'results/b3_0_sources/source_$id.html',
        ).readAsStringSync();
        final v = audit.visibleRecipe(id, source);
        final gt = File(
          '../../test/fixtures/web_import_corpus/batch_3_21-30/recipe_$id.txt',
        ).readAsStringSync();
        final website = File(
          '../../test/fixtures/web_import_corpus/batch_3_21-30/website_$id.txt',
        ).readAsStringSync().trim();
        expect(website, r['url']);
        expect(
          gt.split('HOZZÁVALÓK:').first.replaceFirst('CÍM:', '').trim(),
          v['title'],
        );
        final lines = const LineSplitter()
            .convert(gt.split('HOZZÁVALÓK:').last.split('ELKÉSZÍTÉS:').first)
            .where((l) => l.isNotEmpty && !l.startsWith('['))
            .toList();
        expect(lines, v['ingredients']);
        final refs =
            ((r['instruction_structure_after']
                        as Map<String, dynamic>)['references']
                    as List)
                .cast<Map<String, dynamic>>();
        expect(refs.length, (v['steps']! as List).length);
        expect(
          RegExp(r'^\d+\. @VISIBLE', multiLine: true).allMatches(gt).length,
          refs.length,
        );
        for (final ref in refs) {
          final value = audit.resolveInstruction(
            source,
            ref['selector'] as String,
            ref['selector_index_zero_based'] as int,
            id > 15,
          );
          expect(value.length, ref['text_length']);
          expect(value, isNotEmpty);
        }
      }
    },
  );
  test('unresolved references remain unchanged and excluded', () {
    final old =
        jsonDecode(
              File(
                'results/b3_0_sources/ground_truth_before.json',
              ).readAsStringSync().replaceFirst('\ufeff', ''),
            )
            as Map<String, dynamic>;
    for (final id in [29, 30]) {
      expect(
        File(
          '../../test/fixtures/web_import_corpus/batch_3_21-30/recipe_$id.txt',
        ).readAsStringSync(),
        old['$id'],
      );
    }
  });
}
