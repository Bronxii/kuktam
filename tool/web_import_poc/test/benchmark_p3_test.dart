import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import '../bin/benchmark_p3.dart' as benchmark;

void main() {
  final report =
      jsonDecode(File('results/p3_parser_batch_01-10.json').readAsStringSync())
          as Map<String, dynamic>;
  final rows = (report['rows'] as List).cast<Map<String, dynamic>>();
  test('100 real input rows, source exclusions anchored to P2.5 evidence', () {
    expect(rows.length, 100);
    expect(benchmark.expected.expand((r) => r).length, 100);
    for (final r in rows) {
      expect(
        r['included_in_parser_accuracy'],
        (r['source_evidence'] as List).isEmpty,
      );
    }
    expect(
      rows.where((r) => r['included_in_parser_accuracy'] == false).length,
      22,
    );
  });
  test(
    'unsupported units are not silently scored as correct canonical units',
    () {
      final unsupported = rows.where(
        (r) => r['parser_verdict'] == 'UNSUPPORTED_UNIT',
      );
      expect(unsupported.length, 12);
      for (final r in unsupported) {
        expect(r['unit_correct_against_input'], isNull);
      }
      expect(
        unsupported
            .where((r) => r['included_in_parser_accuracy'] == true)
            .length,
        9,
      );
    },
  );
  test(
    'quantity oracle expresses conversion without invoking production helpers',
    () {
      expect(benchmark.expected[0][3].quantity, 100);
      expect(benchmark.expected[0][3].unit, 'g');
      expect(benchmark.expected[4][7].quantity, 50);
      expect(benchmark.expected[4][7].unit, 'ml');
    },
  );
  test('every measured row retains raw input and recipe context agrees', () {
    final p1 =
        jsonDecode(File('results/p1_batch_01-10.json').readAsStringSync())
            as Map<String, dynamic>;
    final raw = (p1['results'] as List)
        .expand(
          (r) => ((r as Map<String, dynamic>)['candidates'] as List)
              .map((c) => (c as Map<String, dynamic>)['ingredients'] as List)
              .expand((v) => v),
        )
        .toList();
    expect(rows.map((r) => r['raw_extracted_text']).toList(), raw);
    for (final r in (report['recipes'] as List).cast<Map<String, dynamic>>()) {
      expect(r['whole_recipe_vs_single_row_equal'], isTrue);
    }
  });
}
