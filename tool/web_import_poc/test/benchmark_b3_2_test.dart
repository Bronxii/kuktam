import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import '../bin/benchmark_b3_2.dart' as b;

void main() {
  test(
    'B3 offline references, snapshot reconciliation and lossless output',
    () {
      final report = b.measure();
      expect(
        report,
        jsonDecode(
          File('results/b3_2_content_source_quality.json').readAsStringSync(),
        ),
      );
      final rows = (report['recipes'] as List).cast<Map<String, dynamic>>();
      expect(rows.map((r) => r['id']), [for (var i = 21; i <= 28; i++) '$i']);
      expect(
        rows
            .where((r) => (r['snapshot'] as Map)['html_changed'] == true)
            .map((r) => r['id']),
        ['21', '24'],
      );
      for (final row in rows) {
        expect(row['extractor_verdict'], 'LOSSLESS');
        expect((row['reference_check'] as Map)['exact_text_match'], true);
        for (final area in ['ingredients', 'instructions']) {
          expect(
            ((row['extractor_evidence'] as Map)[area]
                as Map)['exact_ordered_equality'],
            true,
          );
        }
      }
      final preservation =
          (report['summary'] as Map)['extractor_data_preservation'] as Map;
      expect(preservation['ingredient_rows'], 82);
      expect(preservation['instruction_entries'], 47);
      expect(
        rows.fold<int>(
          0,
          (n, r) => n + (r['group_heading_differences'] as List).length,
        ),
        4,
      );
    },
  );
  test('blocked sources excluded from content denominators, not technical', () {
    final report = b.measure();
    final blocked = (report['access_blocked'] as List)
        .cast<Map<String, dynamic>>();
    expect(blocked.map((r) => r['id']), ['29', '30']);
    for (final row in blocked) {
      expect(row['http_status'], 403);
      expect(row['status'], 'ACCESS_BLOCKED');
      expect(row['content_status'], 'UNRESOLVED_CONTENT');
      expect(row['extractor_content_verdict'], isNull);
    }
    expect((report['denominators'] as Map)['technical'], 10);
    expect((report['denominators'] as Map)['source_quality_recipes'], 8);
    expect((report['denominators'] as Map)['extractor_recipes'], 8);
  });
}
