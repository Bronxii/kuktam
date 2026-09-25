import 'dart:io';
import 'package:test/test.dart';
import '../bin/benchmark_b2_4.dart' as b;
import '../bin/e2e_simulation.dart' as e;

void main() {
  final report = b.read('b2_4_e2e_batch_11-20.json');
  final rows = (report['recipes'] as List).cast<Map<String, dynamic>>();
  test('deterministic usability thresholds', () {
    expect(b.verdict(0, 10, true), 'READY');
    expect(b.verdict(3, 10, true), 'REVIEW');
    expect(b.verdict(4, 20, true), 'POOR');
    expect(b.verdict(2, 5, true), 'POOR');
    expect(b.verdict(0, 0, false), 'BROKEN');
  });
  test('all rows preserve B2.3 production fields; POC flags are separate', () {
    final prior = (b.read('b2_3_parser_batch_11-20.json')['rows'] as List)
        .cast<Map<String, dynamic>>();
    var count = 0;
    for (final recipe in rows) {
      final draft = recipe['draft'] as Map;
      expect(draft['spices'], isEmpty);
      final ingredients = (draft['ingredients'] as List)
          .cast<Map<String, dynamic>>();
      for (var i = 0; i < ingredients.length; i++) {
        final r = ingredients[i];
        count++;
        final p = prior.singleWhere(
          (p) => p['id'] == recipe['id'] && p['row'] == i + 1,
        );
        expect(r['rawText'], p['raw_extracted_text']);
        expect(r['name'], p['parsed_name']);
        expect(r['quantity'], p['parsed_quantity']);
        expect(r['canonical_unit'], p['parsed_unit']);
        expect(r['warnings'], p['warnings']);
        if (r['unsupported'] == true)
          expect(r['pocWarnings'], contains('UNSUPPORTED_INPUT'));
        expect(
          r['silentFallbackRisk'],
          r['sourceError'] == false &&
              r['unsupported'] == true &&
              (r['warnings'] as List).isEmpty,
        );
      }
    }
    expect(count, 110);
  });
  test('title scope and ordered instruction text preserved', () {
    expect(
      e.displayTitle('Test | Mindmegette.hu', 'https://example.org/a'),
      'Test | Mindmegette.hu',
    );
    expect(
      e.displayTitle('Test | Mindmegette.hu', 'https://www.mindmegette.hu/a'),
      'Test',
    );
    final original = (b.read('b2_1_batch_11-20.json')['results'] as List)
        .cast<Map<String, dynamic>>();
    for (final r in rows) {
      final c =
          (original.singleWhere((x) => x['id'] == r['id'])['candidates']
                      as List)
                  .single
              as Map;
      final preparation = (r['draft'] as Map)['preparation'] as String;
      var position = 0;
      for (final item
          in (c['instructions'] as List).cast<Map<String, dynamic>>()) {
        final text = e.displayText(item['text'] as String);
        final found = preparation.indexOf(text, position);
        expect(
          found,
          greaterThanOrEqualTo(position),
          reason: '${r['id']}: lost/reordered text',
        );
        position = found + text.length;
      }
      expect(
        File('results/b2_4_previews/recipe_${r['id']}.md').existsSync(),
        true,
      );
    }
  });
  test('overlaps are counted once and domain totals reconcile', () {
    final summary = report['summary'] as Map;
    expect(summary['required_correction_rows'], 37);
    expect(summary['required_correction_actions'], 38);
    expect(summary['silent_fallback_risk_rows'], 27);
    expect(summary['source_error_rows'], 2);
    expect(summary['unsupported_rows'], 36);
    expect(
      (summary['clean_rows'] as int) + (summary['warning_rows'] as int),
      110,
    );
    expect(summary['verdicts'], {
      'READY': 0,
      'REVIEW': 5,
      'POOR': 5,
      'BROKEN': 0,
    });
  });
}
