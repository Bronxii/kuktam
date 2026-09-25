// Offline B3.4 only. Reuses the POC normalizer and unchanged production parser.
import 'dart:convert';
import 'dart:io';
import 'e2e_simulation.dart';

Map<String, dynamic> read(String n) =>
    jsonDecode(File('results/$n').readAsStringSync()) as Map<String, dynamic>;
String verdict(int required, int ingredientRows, bool usable) => !usable
    ? 'BROKEN'
    : required == 0
    ? 'READY'
    : required >= 4 || required / ingredientRows >= 0.4
    ? 'POOR'
    : 'REVIEW';
Map<String, Object?> summarize(List<Map<String, Object?>> recipes) {
  final rows = recipes
      .expand(
        (r) => ((r['draft'] as Map)['ingredients'] as List)
            .cast<Map<String, Object?>>(),
      )
      .toList();
  int count(String key) => rows.where((r) => r[key] == true).length;
  return {
    'recipes': recipes.length,
    'verdicts': {
      for (final s in ['READY', 'REVIEW', 'POOR', 'BROKEN'])
        s: recipes.where((r) => r['verdict'] == s).length,
    },
    'total_rows': rows.length,
    'clean_rows': rows
        .where(
          (r) =>
              (r['pocWarnings'] as List).isEmpty &&
              (r['warnings'] as List).isEmpty,
        )
        .length,
    'source_error_rows': count('sourceError'),
    'unsupported_rows': count('unsupported'),
    'parser_error_rows': count('parserError'),
    'warning_rows': rows
        .where(
          (r) =>
              (r['pocWarnings'] as List).isNotEmpty ||
              (r['warnings'] as List).isNotEmpty,
        )
        .length,
    'production_warning_rows': rows
        .where((r) => (r['warnings'] as List).isNotEmpty)
        .length,
    'silent_fallback_risk_rows': count('silentFallbackRisk'),
    'silent_fallback_affected_recipes': recipes
        .where((r) => r['silent_fallback_rows'] != 0)
        .length,
    'required_correction_rows': count('requiredCorrection'),
    'review_only_rows': recipes.fold<int>(
      0,
      (n, r) => n + (r['review_only'] as List).length,
    ),
    'source_structure_warning_rows': 0,
    'source_structure_warning_count': recipes.fold<int>(
      0,
      (n, r) => n + (r['structural_corrections'] as int),
    ),
    'source_structure_affected_recipes': recipes
        .where((r) => r['structural_corrections'] != 0)
        .length,
    'instruction_entries_preserved': recipes.fold<int>(
      0,
      (n, r) => n + (r['instruction_entries_preserved'] as int),
    ),
    'required_correction_actions': recipes.fold<int>(
      0,
      (n, r) => n + (r['required_corrections'] as List).length,
    ),
    'avg_required_corrections':
        recipes.fold<int>(
          0,
          (n, r) => n + (r['required_corrections'] as List).length,
        ) /
        recipes.length,
    'avg_review_only':
        recipes.fold<int>(0, (n, r) => n + (r['review_only'] as List).length) /
        recipes.length,
  };
}

void main() {
  final b1 = read('b3_1_batch_21-30.json'),
      b2 = read('b3_2_content_source_quality.json'),
      b3 = read('b3_3_parser_batch_21-28.json');
  final results = <Map<String, Object?>>[];
  Directory('results/b3_4_previews').createSync(recursive: true);
  for (var i = 21; i <= 28; i++) {
    final id = '$i';
    final source = (b1['results'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((r) => r['id'] == id);
    final quality = (b2['recipes'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((r) => r['id'] == id);
    if ((quality['snapshot'] as Map)['verdict'] != 'UNCHANGED_RECIPE_CONTENT' ||
        (quality['reference_check'] as Map)['exact_text_match'] != true)
      throw StateError('Unreconciled reference');
    final candidate =
        (source['candidates'] as List).single as Map<String, dynamic>;
    final simulation = simulate(candidate, source['url'] as String);
    final draft = simulation['draft'] as Map<String, Object?>;
    final rows = (draft['ingredients'] as List).cast<Map<String, Object?>>();
    final inputs = (candidate['ingredients'] as List).cast<String>();
    if (rows.length != inputs.length) throw StateError('Ingredient loss');
    final corrections = <Map<String, Object?>>[],
        review = <Map<String, Object?>>[];
    for (var j = 0; j < rows.length; j++) {
      final row = rows[j];
      final p = (b3['rows'] as List).cast<Map<String, dynamic>>().singleWhere(
        (r) => r['id'] == id && r['row'] == j + 1,
      );
      if (row['rawText'] != inputs[j] ||
          row['name'] != p['parsed_name'] ||
          row['quantity'] != p['parsed_quantity'] ||
          row['canonical_unit'] != p['parsed_unit'] ||
          jsonEncode(row['warnings']) != jsonEncode(p['warnings']))
        throw StateError('Context mismatch $id/${j + 1}');
      final sourceError = p['source_status'] == 'SOURCE_ERROR';
      final unsupported =
          p['verdict'] == 'UNSUPPORTED_UNIT' ||
          p['verdict'] == 'PARSER_LIMITATION';
      final parserError = !sourceError && p['verdict'] == 'PARSER_ERROR';
      final silent = p['silent_fallback'] == true;
      final required = sourceError || unsupported || parserError;
      row.addAll({
        'sourceIngredientIndex': j,
        'source_status': p['source_status'],
        'parser_status': p['verdict'],
        'sourceError': sourceError,
        'unsupported': unsupported,
        'parserError': parserError,
        'silentFallbackRisk': silent,
        'requiredCorrection': required,
        'pocWarnings': [
          if (sourceError) 'SOURCE_WARNING',
          if (unsupported) 'UNSUPPORTED_INPUT',
          if (p['verdict'] == 'PARSER_LIMITATION') 'PARSER_LIMITATION',
          if (parserError) 'PARSER_WARNING',
          if (silent) 'SILENT_BAD_FALLBACK_RISK',
        ],
        'source_evidence': p['source_quality'],
        'unsupported_phrase': p['unsupported_phrase'],
        'misleading_fields': [
          if (unsupported && p['unit_correct'] != true) 'canonical_unit',
          if (unsupported && p['quantity_correct'] != true)
            'quantity interpretation',
          if (unsupported && p['name_correct'] != true)
            'name contains unresolved measure/expression',
        ],
      });
      if (required) {
        corrections.add({
          'row': j + 1,
          'classification': 'REQUIRED_CORRECTION',
          'fields': [
            if (sourceError) 'name/source note',
            if (unsupported) 'name/quantity/unit interpretation',
            if (parserError) 'parsed fields',
          ],
          'reasons': [
            if (sourceError)
              'Visible source note lost in JSON-LD; not repaired.',
            if (unsupported)
              'Unsupported measure/expression cannot safely be represented by current db fallback.',
            if (parserError) 'Supported-input parser mismatch.',
          ],
          'counting':
              'One row-level correction action even if multiple fields/reasons overlap.',
        });
      } else if ((row['warnings'] as List).isNotEmpty) {
        review.add({
          'row': j + 1,
          'field': 'quantity',
          'classification': 'REVIEW_ONLY',
          'reason':
              'Source gives no quantity; accepted 1 db default requires confirmation, not a proven erroneous value.',
        });
      }
    }
    final groups = quality['group_heading_differences'] as List;
    for (final g in groups) {
      corrections.add({
        'field': 'ingredient grouping',
        'classification': 'REQUIRED_CORRECTION',
        'reason':
            'Ingredient group heading lost upstream; logical grouping/to-serve/optional scope needs manual representation. No automatic restoration or ingredient insertion.',
        'evidence': g,
        'counting':
            'One recipe-level structural correction; may need a note/workaround because current draft has no group field.',
      });
    }
    final usable =
        (draft['title'] as String).trim().isNotEmpty &&
        rows.isNotEmpty &&
        (draft['preparation'] as String).isNotEmpty;
    if (draft['preparation'] != simulation['normalized_preparation'])
      throw StateError('Preparation loss');
    final label = verdict(corrections.length, rows.length, usable);
    if (simulation['raw_title'] != simulation['normalized_title'] ||
        draft['title'] != simulation['raw_title'])
      throw StateError('Unexpected title mutation');
    var position = 0;
    final entries = (candidate['instructions'] as List)
        .cast<Map<String, dynamic>>();
    for (final entry in entries) {
      final text = displayText(entry['text'] as String);
      final found = (draft['preparation'] as String).indexOf(text, position);
      if (found < position) throw StateError('Lost or reordered instruction');
      position = found + text.length;
    }
    final record = <String, Object?>{
      'id': id,
      'url': source['url'],
      'domain': source['domain'],
      ...simulation,
      'title_changed': false,
      'ingredient_count': rows.length,
      'clean_rows': rows
          .where(
            (r) =>
                (r['warnings'] as List).isEmpty &&
                (r['pocWarnings'] as List).isEmpty,
          )
          .length,
      'unsupported_rows': rows.where((r) => r['unsupported'] == true).length,
      'structural_corrections': groups.length,
      'source_structure_warnings': [
        for (final g in groups)
          {'type': 'SOURCE_STRUCTURE_WARNING', 'evidence': g},
      ],
      'instruction_entries_preserved': entries.length,
      'required_corrections': corrections,
      'review_only': review,
      'silent_fallback_rows': rows
          .where((r) => r['silentFallbackRisk'] == true)
          .length,
      'verdict': label,
      'verdict_reason':
          '${corrections.length} correction actions / ${rows.length} ingredient rows; ${review.length} review-only quantities. Usable=$usable.',
      'consistency': {
        'ingredient_fields_equal_b3_3': true,
        'preparation_equals_normalized_input': true,
        'b3_0_reference_verified_by_b3_2': true,
      },
    };
    results.add(record);
    final md = StringBuffer('RECEPT:\n${draft['title']}\n\nHOZZÁVALÓK:\n');
    for (final row in rows) {
      md.writeln(
        '- ${row['quantity'] ?? '[javítandó]'} ${row['canonical_unit']} ${row['name']}',
      );
    }
    md.writeln(
      '\nWARNINGS:\nProduction és POC jelzések külön; a POC jelzések kézi benchmark-besorolásból származnak, nem runtime felismerésből.',
    );
    for (var j = 0; j < rows.length; j++) {
      final r = rows[j];
      if ((r['warnings'] as List).isNotEmpty ||
          (r['pocWarnings'] as List).isNotEmpty)
        md.writeln(
          '- ${j + 1}: production=${r['warnings']}; POC=${r['pocWarnings']}',
        );
    }
    if (groups.isNotEmpty)
      md.writeln(
        '- SOURCE_STRUCTURE_WARNING: missing ingredient group heading: $groups',
      );
    md.writeln(
      '\nELKÉSZÍTÉS:\n${draft['preparation']}\n\nVERDICT:\n$label — ${record['verdict_reason']}\n\nREQUIRED CORRECTIONS:',
    );
    for (final c in corrections) {
      md.writeln('- ${jsonEncode(c)}');
    }
    md.writeln('\nREVIEW ONLY:');
    for (final r in review) {
      md.writeln('- ${jsonEncode(r)}');
    }
    File(
      'results/b3_4_previews/recipe_$id.md',
    ).writeAsStringSync('${md.toString().trimRight()}\n');
  }
  final summary = summarize(results);
  final timing = <String, Object?>{};
  for (final key in [
    'normalization_ms',
    'parser_ms',
    'draft_build_ms',
    'total_local_ms',
  ]) {
    final values = results
        .map((r) => ((r['timing'] as Map)[key] as num).toDouble())
        .toList();
    timing[key] = {
      'total': values.reduce((a, b) => a + b),
      'average': values.reduce((a, b) => a + b) / values.length,
      'max': values.reduce((a, b) => a > b ? a : b),
    };
  }
  final report = {
    'method':
        'Offline B3.4, 21–28 only. Existing POC simulate() invokes unchanged production RecipeTextParser on full title/ingredients/preparation. Raw ingredient input and production warnings untouched. All eight clean Good Food titles unchanged. POC warning metadata uses B3.2/B3.3 human-audited labels, NOT an implemented online detector. No correction applied.',
    'counting_policy':
        'Required: one action per objectively misleading ingredient row. All 31 reviewed unsupported rows here contain a measure/expression represented as db or an ambiguous/null quantity, so they require resolution (not merely review); original words remain but do not make that numeric/unit representation reliable. Count overlapping reasons counted once; plus one action per missing source ingredient group. Review-only: non-required rows with accepted missing-quantity fallback. Clean means no production OR POC warning. Source/unsupported/warning/risk categories overlap. Source-error rows excluded from silent risk, not excluded from user correction needs.',
    'thresholds':
        'BROKEN if title/preparation empty or no ingredient rows. READY if 0 required actions. POOR if >=4 required actions OR required actions / ingredient rows >=40%. Otherwise REVIEW. Group loss counts one structural action and cannot necessarily be restored in existing editor without notes; no new editor support assumed.',
    'timing_note':
        'Desktop Dart JIT, one sequential pass, first recipe includes cold/JIT. Core normalization/parser/draft assembly only; file IO, metadata adjudication and preview/report formatting outside timers. No network.',
    'excluded': {
      '29': 'NO_DRAFT_DUE_TO_ACCESS_BLOCK',
      '30': 'NO_DRAFT_DUE_TO_ACCESS_BLOCK',
    },
    'comparison_b2_4': read('b2_4_e2e_batch_11-20.json')['summary'],
    'summary': summary,
    'domains': {
      for (final domain in results.map((r) => r['domain'] as String).toSet())
        domain: summarize(results.where((r) => r['domain'] == domain).toList()),
    },
    'timing': timing,
    'recipes': results,
  };
  const encoder = JsonEncoder.withIndent('  ');
  File(
    'results/b3_4_e2e_batch_21-28.json',
  ).writeAsStringSync('${encoder.convert(report)}\n');
  final md = StringBuffer(
    '# B3.4 – End-to-end draft simulation, 21–28\n\n${report['method']}\n\n${report['counting_policy']}\n\n${report['thresholds']}\n\n${report['timing_note']}\n\n',
  );
  md.writeln(
    '## Summary\n\n```json\n${encoder.convert({'summary': summary, 'domains': report['domains'], 'timing': timing})}\n```\n',
  );
  md.writeln(
    '| ID | Rows | Clean | Unsupported | Silent | Structural | Required actions | Review only | Verdict | Preview |\n|---|---|---|---|---|---|---|---|---|---|',
  );
  for (final r in results) {
    md.writeln(
      '| ${r['id']} | ${r['ingredient_count']} | ${r['clean_rows']} | ${r['unsupported_rows']} | ${r['silent_fallback_rows']} | ${r['structural_corrections']} | ${(r['required_corrections'] as List).length} | ${(r['review_only'] as List).length} | ${r['verdict']} | [preview](b3_4_previews/recipe_${r['id']}.md) |',
    );
  }
  md.writeln(
    '\nTitles: 8/8 unchanged. All 47 source instruction entries preserved in order, without duplicate headings. Spices empty. Four missing group headings are source structure warnings, not parser errors; 25 loses filling/crumble/optional-topping scopes, 28 loses To serve scope. They are counted as four separate structural correction actions, not ingredient rows. Ingredient categories overlap; clean + warning rows partitions all 82 rows.',
  );
  md.writeln(
    '\n## B2.4 comparison\n\nB2.4: 0 READY / 5 REVIEW / 5 POOR / 0 BROKEN; 3.8 required actions per recipe; 27 silent fallback rows. B3.4 summary above uses the same one-row-one-action rule and one action per missing group heading. Different sample sizes (10 vs 8), no pooled statistics. Structural actions count toward the >=4 threshold; the 40% rule in this corpus gives the same result whether structural actions are included or only corrected ingredient rows are used.',
  );
  md.writeln(
    '\nNo parser modification is needed before B3.5 summary. This is a supervised POC, not safe unattended production import. Production warnings and audit-derived POC warnings are distinct; no runtime unsupported detector was implemented. 29–30: NO_DRAFT_DUE_TO_ACCESS_BLOCK, HTTP 403, excluded from usability denominator. No production, extractor, parser or corpus changes. B3.5 not started.',
  );
  File(
    'results/b3_4_e2e_batch_21-28.md',
  ).writeAsStringSync('${md.toString().trimRight()}\n');
  stdout.writeln(
    encoder.convert({
      'summary': summary,
      'domains': report['domains'],
      'timing': timing,
    }),
  );
}
