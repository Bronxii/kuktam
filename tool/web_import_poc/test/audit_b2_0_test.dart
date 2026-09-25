import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import '../bin/audit_b2_0.dart' as audit;

void main() {
  test(
    'batch 2 corpus matches visible DOM; every instruction reference resolves',
    () {
      final report =
          jsonDecode(
                File('results/b2_0_source_truth_audit.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      final recipes = (report['recipes'] as List).cast<Map<String, dynamic>>();
      expect(recipes.map((r) => r['id']).toList(), [
        for (var id = 11; id <= 20; id++) '$id',
      ]);
      for (final r in recipes) {
        final id = int.parse(r['id'] as String);
        final source = File(
          'results/b2_0_sources/source_$id.html',
        ).readAsStringSync();
        final v = audit.visibleRecipe(id, source);
        final gt = File(
          '../../test/fixtures/web_import_corpus/batch_2_11-20/recipe_$id.txt',
        ).readAsStringSync();
        final website = File(
          '../../test/fixtures/web_import_corpus/batch_2_11-20/website_$id.txt',
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
  test('source quantity and note spellings retained without conversion', () {
    String recipe(int id) => File(
      '../../test/fixtures/web_import_corpus/batch_2_11-20/recipe_$id.txt',
    ).readAsStringSync();
    expect(recipe(18), contains('½ tsp dried marjoram'));
    expect(recipe(19), contains('2 x 400g cans chopped tomatoes'));
    expect(recipe(19), contains('2-3 tbsp mango chutney'));
    expect(recipe(17), contains('half a 340g jar good-quality strawberry jam'));
    expect(recipe(17), contains('[For the filling]'));
    expect(recipe(20), contains('torn (optional)'));
  });
  test('line diff handles merged ingredient without positional cascade', () {
    final changes = audit.changes(
      ['a', 'salt', 'pepper', 'b'],
      ['a', 'salt and pepper', 'b'],
    );
    expect(changes.length, 2);
    expect(changes.where((c) => c['operation'] == 'remove').length, 1);
  });
}
