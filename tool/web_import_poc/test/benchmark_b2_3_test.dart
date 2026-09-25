import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';

void main() {
  final report =
      jsonDecode(
            File('results/b2_3_parser_batch_11-20.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  final rows = (report['rows'] as List).cast<Map<String, dynamic>>();
  test(
    'source errors are excluded and classification partitions valid rows',
    () {
      final s = report['summary'] as Map;
      expect(rows.length, 110);
      expect(s['valid_source'], 108);
      expect(
        (s['correct'] as int) +
            (s['parser_errors'] as int) +
            (s['unsupported'] as int),
        108,
      );
      expect(
        rows
            .where((r) => r['primary_classification'] == 'SOURCE_ERROR')
            .map((r) => '${r['id']}/${r['row']}')
            .toList(),
        ['14/8', '14/9'],
      );
    },
  );
  test('frozen input matches B2.1 and context retains every row', () {
    final b1 =
        jsonDecode(File('results/b2_1_batch_11-20.json').readAsStringSync())
            as Map<String, dynamic>;
    for (final r in (b1['results'] as List).cast<Map<String, dynamic>>()) {
      final c = (r['candidates'] as List).single as Map;
      expect(
        rows
            .where((x) => x['id'] == r['id'])
            .map((x) => x['raw_extracted_text'])
            .toList(),
        c['ingredients'],
      );
    }
    for (final r in (report['recipes'] as List).cast<Map<String, dynamic>>()) {
      expect(r['whole_vs_single_equal'], true);
    }
  });
  test('unsupported expressions are not silently scored as successful', () {
    Map<String, dynamic> row(String id, int n) =>
        rows.singleWhere((r) => r['id'] == id && r['row'] == n);
    expect(row('19', 9)['primary_classification'], 'UNSUPPORTED_UNIT');
    expect(row('19', 9)['quantity_correct'], null);
    expect(row('19', 9)['parsed_quantity'], 1);
    expect(row('19', 7)['parsed_quantity'], null);
    expect(row('18', 11)['parsed_quantity'], 0.5);
    expect(row('18', 11)['parsed_unit'], 'db');
    expect(row('18', 11)['primary_classification'], 'UNSUPPORTED_UNIT');
  });
}
