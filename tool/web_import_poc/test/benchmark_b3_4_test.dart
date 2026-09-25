import 'package:test/test.dart';
import '../bin/benchmark_b3_4.dart' as b;
import '../bin/e2e_simulation.dart' as e;
import 'dart:io';

void main() {
  final report = b.read('b3_4_e2e_batch_21-28.json');
  final recipes = (report['recipes'] as List).cast<Map<String, dynamic>>();
  test('B3.4 is restricted to eight recipes; accounting reconciles', () {
    expect(recipes.map((r) => r['id']), [for (var i = 21; i <= 28; i++) '$i']);
    final s = report['summary'] as Map;
    expect(s['verdicts'], {'READY': 1, 'REVIEW': 2, 'POOR': 5, 'BROKEN': 0});
    expect(s['total_rows'], 82);
    expect(s['required_correction_rows'], 31);
    expect(s['required_correction_actions'], 35);
    expect(s['review_only_rows'], 6);
    expect(s['clean_rows'], 45);
    expect(s['warning_rows'], 37);
    expect(s['source_structure_warning_count'], 4);
    expect(s['parser_error_rows'], 0);
    expect(s['silent_fallback_risk_rows'], 21);
    expect(s['silent_fallback_affected_recipes'], 6);
    expect((report['excluded'] as Map).keys, containsAll(['29', '30']));
    expect(File('results/b3_4_previews/recipe_29.md').existsSync(), false);
    expect(File('results/b3_4_previews/recipe_30.md').existsSync(), false);
  });
  test('full-context replay preserves production fields and all 47 steps', () {
    final inputs = (b.read('b3_1_batch_21-30.json')['results'] as List)
        .cast<Map<String, dynamic>>();
    final prior = (b.read('b3_3_parser_batch_21-28.json')['rows'] as List)
        .cast<Map<String, dynamic>>();
    var steps = 0;
    for (final r in recipes) {
      final original = inputs.singleWhere((x) => x['id'] == r['id']);
      final c = (original['candidates'] as List).single as Map<String, dynamic>;
      final sim = e.simulate(c, r['url'] as String);
      final draft = r['draft'] as Map;
      expect(draft['title'], c['title']);
      expect(r['title_changed'], false);
      expect(draft['spices'], isEmpty);
      expect(draft['preparation'], (sim['draft'] as Map)['preparation']);
      final entries = (c['instructions'] as List).cast<Map<String, dynamic>>();
      expect(draft['preparation'], e.instructionLines(entries).join('\n\n'));
      steps += entries.where((x) => x['kind'] == 'step').length;
      final rows = (draft['ingredients'] as List).cast<Map<String, dynamic>>();
      final replay = ((sim['draft'] as Map)['ingredients'] as List)
          .cast<Map<String, dynamic>>();
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        final p = prior.singleWhere(
          (x) => x['id'] == r['id'] && x['row'] == i + 1,
        );
        for (final key in [
          'rawText',
          'name',
          'quantity',
          'canonical_unit',
          'warnings',
          'sourceOrder',
        ]) {
          expect(row[key], replay[i][key]);
        }
        expect(row['warnings'], p['warnings']);
        expect(row['silentFallbackRisk'], p['silent_fallback']);
        if (row['unsupported'] == true)
          expect(row['pocWarnings'], contains('UNSUPPORTED_INPUT'));
      }
      expect(
        File('results/b3_4_previews/recipe_${r['id']}.md').existsSync(),
        true,
      );
    }
    expect(steps, 47);
  });
  test(
    'same B2.4 thresholds and structural corrections counted separately',
    () {
      expect(b.verdict(0, 10, true), 'READY');
      expect(b.verdict(3, 10, true), 'REVIEW');
      expect(b.verdict(4, 20, true), 'POOR');
      expect(b.verdict(2, 5, true), 'POOR');
      expect(b.verdict(0, 0, false), 'BROKEN');
      for (final r in recipes) {
        final rows = ((r['draft'] as Map)['ingredients'] as List)
            .cast<Map<String, dynamic>>();
        final n = rows.where((x) => x['requiredCorrection'] == true).length;
        expect(
          (r['required_corrections'] as List).length,
          n + (r['structural_corrections'] as int),
        );
        expect(
          r['verdict'],
          b.verdict(
            (r['required_corrections'] as List).length,
            rows.length,
            true,
          ),
        );
      }
    },
  );
}
