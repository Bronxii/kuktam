import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import '../bin/benchmark_b2_2.dart' as b;

void main() {
  test('comparison detects dropped, added, changed and reordered entries', () {
    expect(b.listEvidence(['a', 'b'], ['a'])['lost'], 1);
    expect(b.listEvidence(['a'], ['a', 'b'])['added'], 1);
    expect(b.listEvidence(['a'], ['b'])['modified_positions'], [1]);
    expect(b.listEvidence(['a', 'b'], ['b', 'a'])['order_error'], true);
    expect(b.listEvidence(['a', 'a'], ['a'])['lost'], 1);
  });
  test(
    'comparison normalizes format only, retains ranges and missing notes',
    () {
      expect(
        b.ingredientVerdict('1 tsp baking powder', '1 tsp  baking powder'),
        'FORMAT_DIFFERENCE',
      );
      expect(
        b.ingredientVerdict('1 fej káposzta (1,5 kg)', '1 fej káposzta'),
        'MISSING_NOTE',
      );
      expect(
        b.ingredientVerdict('2-3 tbsp chutney', '2 tbsp chutney'),
        'OTHER_CONTENT_DIFFERENCE',
      );
      expect(
        b.ingredientVerdict('½ tsp salt', '1 tsp salt'),
        'OTHER_CONTENT_DIFFERENCE',
      );
    },
  );
  test(
    'instruction source inventory preserves headings and ordered bodies',
    () {
      expect(
        b.instructionLeaves({
          '@type': 'HowToSection',
          'name': 'Section',
          'itemListElement': [
            {'@type': 'HowToStep', 'name': 'Step', 'text': 'Body'},
            'Second',
          ],
        }),
        [
          {'kind': 'section', 'text': 'Section'},
          {'kind': 'heading', 'text': 'Step'},
          {'kind': 'step', 'text': 'Body'},
          {'kind': 'step', 'text': 'Second'},
        ],
      );
    },
  );
  test('frozen B2.0 references and B2.1 output reconcile offline', () {
    final report = b.measure();
    expect(
      report,
      jsonDecode(
        File('results/b2_2_content_source_quality.json').readAsStringSync(),
      ),
    );
    final rows = (report['recipes'] as List).cast<Map<String, dynamic>>();
    expect(rows.map((r) => r['id']).toList(), [
      for (var id = 11; id <= 20; id++) '$id',
    ]);
    for (final r in rows) {
      expect(r['extractor_verdict'], 'LOSSLESS');
      final evidence = r['extractor_evidence'] as Map;
      expect((evidence['ingredients'] as Map)['exact_ordered_equality'], true);
      expect((evidence['instructions'] as Map)['exact_ordered_equality'], true);
      expect((r['reference_check'] as Map)['exact_text_match'], true);
    }
    final summary = report['summary'] as Map;
    expect(
      (summary['snapshot_stability'] as Map)['technical_html_changes_only'],
      8,
    );
    expect(
      ((summary['source_quality'] as Map)['ingredients']
          as Map)['exact_or_normalized_matches'],
      108,
    );
    expect(
      (rows.singleWhere((r) => r['id'] == '12')['instructions']
          as Map)['verdict'],
      'COMPLETE_WITH_STRUCTURE_DIFFERENCE',
    );
  });
}
