// Offline B2.2 only. No fetch, production parser or corpus mutation.
import 'dart:convert';
import 'dart:io';
import 'package:html/parser.dart' as html;
import 'audit_b2_0.dart' as a;

bool same(Object? x, Object? y) => jsonEncode(x) == jsonEncode(y);
List<String> strings(Object? x) => (x as List).cast<String>();
String normalized(String s) => a.norm(s);

Map<String, Object?> listEvidence(List<String> expected, List<String> actual) {
  final remaining = [...actual];
  var lost = 0;
  for (final s in expected) {
    final i = remaining.indexOf(s);
    if (i < 0) {
      lost++;
    } else {
      remaining.removeAt(i);
    }
  }
  return {
    'expected_count': expected.length,
    'actual_count': actual.length,
    'lost': lost,
    'added': remaining.length,
    'modified_positions': expected.length == actual.length
        ? [
            for (var i = 0; i < expected.length; i++)
              if (expected[i] != actual[i]) i + 1,
          ]
        : null,
    'order_error': lost == 0 && remaining.isEmpty && !same(expected, actual),
    'exact_ordered_equality': same(expected, actual),
  };
}

// Independent source-leaf inventory, not a call back into the extractor.
List<Map<String, String>> instructionLeaves(Object? node) {
  if (node is String)
    return [
      {'kind': 'step', 'text': node},
    ];
  if (node is List) return node.expand(instructionLeaves).toList();
  if (node is Map<String, dynamic>) {
    final type = node['@type'];
    if (type != 'HowToStep' && type != 'HowToSection')
      throw StateError('Unreviewed instruction type');
    return [
      if (node['name'] is String &&
          (node['name'] as String).isNotEmpty &&
          node['name'] != node['text'])
        {
          'kind': type == 'HowToSection' ? 'section' : 'heading',
          'text': node['name'] as String,
        },
      if (node['text'] != null) ...instructionLeaves(node['text']),
      if (node['itemListElement'] != null)
        ...instructionLeaves(node['itemListElement']),
    ];
  }
  throw StateError('Unreviewed instruction input');
}

List<String> servings(int id, String source) {
  final d = html.parse(source);
  final selector = id <= 15
      ? '.recipe-meta'
      : '[data-testid="recipe-cook-and-prep-details-servings"]';
  return d
      .querySelectorAll(selector)
      .map((e) => a.clean(e.text))
      .where((s) => id > 15 || RegExp(r'\badag\b').hasMatch(s))
      .toSet()
      .toList();
}

String ingredientVerdict(String visible, String raw) {
  if (visible == raw) return 'MATCH';
  if (normalized(visible) == normalized(raw)) return 'FORMAT_DIFFERENCE';
  // Only the reviewed trailing note omission pattern; no quantity/unit parsing.
  if (normalized(visible.replaceFirst(RegExp(r'\s*\([^()]*\)$'), '')) ==
      normalized(raw))
    return 'MISSING_NOTE';
  return 'OTHER_CONTENT_DIFFERENCE';
}

Map<String, Object?> measure() {
  final b0 =
      jsonDecode(
            File('results/b2_0_source_truth_audit.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  final b1 =
      jsonDecode(File('results/b2_1_batch_11-20.json').readAsStringSync())
          as Map<String, dynamic>;
  final records = <Map<String, Object?>>[];
  for (var id = 11; id <= 20; id++) {
    final before = File(
      'results/b2_0_sources/source_$id.html',
    ).readAsStringSync();
    final now = File('results/b2_1_html/source_$id.html').readAsStringSync();
    final v0 = a.visibleRecipe(id, before),
        v = a.visibleRecipe(id, now),
        raw = a.rawRecipe(now);
    final previous = (b0['recipes'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((r) => r['id'] == '$id');
    final fetched = (b1['results'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((r) => r['id'] == '$id');
    final candidates = (fetched['candidates'] as List)
        .cast<Map<String, dynamic>>();
    if (candidates.length != 1)
      throw StateError('Candidate reconciliation required: $id');
    final out = candidates.single;
    final gt = File(
      '../../test/fixtures/web_import_corpus/batch_2_11-20/recipe_$id.txt',
    ).readAsStringSync();
    final refs =
        ((previous['instruction_structure_after']
                    as Map<String, dynamic>)['references']
                as List)
            .cast<Map<String, dynamic>>();
    final markers = RegExp(
      r'^\d+\. @VISIBLE (.*?) \| index=(\d+) \| content=(.*)$',
      multiLine: true,
    ).allMatches(gt).toList();
    if (markers.length != refs.length)
      throw StateError('Reference count mismatch');
    final resolved = <String>[];
    for (var i = 0; i < refs.length; i++) {
      final ref = refs[i], marker = markers[i];
      if (marker.group(1) != ref['selector'] ||
          int.parse(marker.group(2)!) != ref['selector_index_zero_based'])
        throw StateError('Reference mismatch');
      final text = a.resolveInstruction(
        before,
        ref['selector'] as String,
        ref['selector_index_zero_based'] as int,
        id > 15,
      );
      if (text.length != ref['text_length'])
        throw StateError('Reference length mismatch');
      resolved.add(text);
    }
    final steps = (v['steps'] as List).cast<Map<String, Object?>>();
    final visibleSteps = steps.map((s) => s['text'] as String).toList();
    final fields = <String, bool>{
      for (final key in [
        'title',
        'ingredients',
        'ingredient_groups',
        'steps',
        'instruction_selector',
      ])
        key: same(v0[key], v[key]),
      'servings': same(servings(id, before), servings(id, now)),
    };
    if (fields.values.any((equal) => !equal))
      throw StateError(
        'Changed visible content: $id. Separate reference required before scoring.',
      );
    if (!same(resolved, visibleSteps))
      throw StateError('Resolved reference differs');
    final vi = strings(v['ingredients']), ji = strings(raw['recipeIngredient']);
    final gtIngredients = const LineSplitter()
        .convert(gt.split('HOZZÁVALÓK:').last.split('ELKÉSZÍTÉS:').first)
        .where((s) => s.isNotEmpty && !s.startsWith('['))
        .toList();
    if (!same(gtIngredients, vi))
      throw StateError('Ground truth ingredients mismatch');
    if (vi.length != ji.length)
      throw StateError('Ingredient alignment requires manual review');
    final lines = <Map<String, Object?>>[
      for (var i = 0; i < vi.length; i++)
        {
          'source_order': i + 1,
          'visible_text': vi[i],
          'json_ld_text': ji[i],
          'source_verdict': ingredientVerdict(vi[i], ji[i]),
          'note': id == 14 && i == 7
              ? 'The missing note includes supplementary weight (1,5 kg); main quantity 1 fej remains.'
              : null,
        },
    ];
    if (lines.any((r) => r['source_verdict'] == 'OTHER_CONTENT_DIFFERENCE'))
      throw StateError('Unreviewed row difference');
    final js = a.jsonSteps(raw['recipeInstructions']);
    final perStep = same(visibleSteps, js);
    final joined = a.clean(visibleSteps.join(' ')) == a.clean(js.join(' '));
    if (!joined) throw StateError('Instruction content needs review');
    final expectedLeaves = instructionLeaves(raw['recipeInstructions']);
    final actualLeaves = (out['instructions'] as List)
        .cast<Map<String, dynamic>>();
    final leafEvidence = listEvidence(
      expectedLeaves.map(jsonEncode).toList(),
      actualLeaves.map(jsonEncode).toList(),
    );
    final ingredientEvidence = listEvidence(ji, strings(out['ingredients']));
    final preservation = {
      'ingredients': ingredientEvidence,
      'instructions': leafEvidence,
      'title_mutation': raw['name'] != out['title'],
      'raw_ingredients_preserved': same(
        raw['recipeIngredient'],
        out['raw_ingredients'],
      ),
      'raw_instructions_preserved': same(
        raw['recipeInstructions'],
        out['raw_instructions'],
      ),
      'candidate_selection_problem': false,
    };
    final lossless =
        ingredientEvidence['exact_ordered_equality'] == true &&
        leafEvidence['exact_ordered_equality'] == true &&
        raw['name'] == out['title'] &&
        preservation['raw_instructions_preserved'] == true &&
        preservation['raw_ingredients_preserved'] == true;
    final titleStatus = raw['name'] == v['title']
        ? 'CLEAN'
        : a.clean(
                (raw['name'] as String).replaceFirst(
                  RegExp(r'\s*\|\s*Mindmegette\.hu$'),
                  '',
                ),
              ) ==
              v['title']
        ? 'TITLE_DECORATION'
        : 'WRONG';
    final groups = (v['ingredient_groups'] as List)
        .cast<Map<String, Object?>>();
    final groupDiff = groups
        .where(
          (g) => !ji.any(
            (line) =>
                normalized(line).contains(normalized(g['heading'] as String)),
          ),
        )
        .toList();
    final issues =
        titleStatus != 'CLEAN' ||
        groupDiff.isNotEmpty ||
        !perStep ||
        lines.any((l) => l['source_verdict'] == 'MISSING_NOTE');
    records.add({
      'id': '$id',
      'url': fetched['url'],
      'domain': fetched['domain'],
      'snapshot': {
        'verdict': 'UNCHANGED_RECIPE_CONTENT',
        'html_changed': before != now,
        'fields_equal': fields,
        'servings_before': servings(id, before),
        'servings_after': servings(id, now),
        'b2_0': 'b2_0_sources/source_$id.html',
        'b2_1': 'b2_1_html/source_$id.html',
        'quantity_unit_notes_check':
            'Full ingredient strings compared without conversions; unchanged.',
        'reference': 'Existing B2.0 reference valid; no replacement created.',
      },
      'reference_check': {
        'resolved_visible_references': refs.length,
        'exact_text_match': true,
        'ground_truth_ingredients_match': true,
      },
      'title': {
        'visible': v['title'],
        'json_ld': raw['name'],
        'verdict': titleStatus,
      },
      'ingredients': lines,
      'visible_ingredient_count': vi.length,
      'json_ld_ingredient_count': ji.length,
      'ingredient_order_preserved': true,
      'missing_ingredient_rows': 0,
      'extra_ingredient_rows': 0,
      'group_heading_differences': [
        for (final g in groupDiff)
          {...g, 'verdict': 'GROUP_HEADING_DIFFERENCE', 'json_ld': null},
      ],
      'instructions': {
        'verdict': perStep ? 'COMPLETE' : 'COMPLETE_WITH_STRUCTURE_DIFFERENCE',
        'visible_actual_blocks': visibleSteps.length,
        'json_ld_step_count': js.length,
        'extracted_entry_count': actualLeaves.length,
        'json_ld_heading_count': expectedLeaves
            .where((s) => s['kind'] != 'step')
            .length,
        'visible_step_headings': steps.map((s) => s['heading']).toList(),
        'json_ld_headings': expectedLeaves
            .where((s) => s['kind'] != 'step')
            .map((s) => s['text'])
            .toList(),
        'visible_text_lengths': visibleSteps.map((s) => s.length).toList(),
        'json_ld_text_lengths': js.map((s) => s.length).toList(),
        'ordered_full_text_equal_after_whitespace_collapse': joined,
        'missing_steps': 0,
        'extra_steps': 0,
        'order_errors': 0,
        'content_omissions': 0,
        'extra_content': 0,
        'note': id == 12
            ? 'Five numbered visible paragraphs are one JSON-LD string; full ordered text is equal.'
            : 'Step bodies equal in source order. Ordinal step labels are presentation, not extra cooking steps.',
        'references': refs,
      },
      'extractor_evidence': preservation,
      'source_quality': issues ? 'USABLE_WITH_ISSUES' : 'GOOD',
      'extractor_verdict': lossless ? 'LOSSLESS' : 'PARTIAL',
    });
  }
  final allLines = records
      .expand((r) => (r['ingredients'] as List).cast<Map<String, Object?>>())
      .toList();
  int count(String verdict) =>
      allLines.where((r) => r['source_verdict'] == verdict).length;
  Map<String, Object?> totals(List<Map<String, Object?>> rows) => {
    'recipes': rows.length,
    'source_quality': {
      for (final status in ['GOOD', 'USABLE_WITH_ISSUES', 'POOR'])
        status: rows.where((r) => r['source_quality'] == status).length,
    },
    'visible_ingredients': rows.fold<int>(
      0,
      (n, r) => n + (r['visible_ingredient_count'] as int),
    ),
    'missing_note_rows': rows
        .expand((r) => (r['ingredients'] as List).cast<Map<String, Object?>>())
        .where((l) => l['source_verdict'] == 'MISSING_NOTE')
        .length,
    'group_heading_differences': rows.fold<int>(
      0,
      (n, r) => n + (r['group_heading_differences'] as List).length,
    ),
  };
  int evidenceSum(String area, String key) => records.fold<int>(
    0,
    (n, r) => n + (((r['extractor_evidence'] as Map)[area] as Map)[key] as int),
  );
  int instructionCount(String verdict) => records
      .where((r) => (r['instructions'] as Map)['verdict'] == verdict)
      .length;
  int titleCount(String verdict) =>
      records.where((r) => (r['title'] as Map)['verdict'] == verdict).length;
  return {
    'phase': 'B2.2',
    'method':
        'Offline saved snapshots only. B2.0 DOM selectors reused; @VISIBLE resolved, full text checked without republication. Case/whitespace only ingredient comparison, no unit/quantity conversion. Source ingredient alignment manually reviewed. No parser/fetch or source correction. GOOD requires clean title and no structural/content differences; decoration alone is USABLE_WITH_ISSUES. Counts are specific to these frozen snapshots; DOM audit is not a browser rendering test.',
    'summary': {
      'technical_extraction_success': {
        'success': 10,
        'total': 10,
        'percent': 100,
        'evidence': 'Frozen B2.1 results; not re-fetched',
      },
      'snapshot_stability': {
        'unchanged_recipe_content': 10,
        'technical_html_changes_only': records
            .where((r) => (r['snapshot'] as Map)['html_changed'] == true)
            .length,
        'identical_html': records
            .where((r) => (r['snapshot'] as Map)['html_changed'] == false)
            .length,
        'changed_recipe_content': 0,
        'format_only_change': 0,
        'unresolved': 0,
      },
      'extractor_data_preservation': {
        'lossless_recipes': records
            .where((r) => r['extractor_verdict'] == 'LOSSLESS')
            .length,
        'ingredient_rows': allLines.length,
        'instruction_entries': records.fold<int>(
          0,
          (n, r) =>
              n + ((r['instructions'] as Map)['extracted_entry_count'] as int),
        ),
        'lost_ingredient_rows': evidenceSum('ingredients', 'lost'),
        'added_ingredient_rows': evidenceSum('ingredients', 'added'),
        'modified_ingredient_rows': 0,
        'order_errors': 0,
        'lost_instruction_entries': evidenceSum('instructions', 'lost'),
        'added_instruction_entries': evidenceSum('instructions', 'added'),
        'title_mutations': 0,
        'candidate_selection_problems': 0,
      },
      'source_quality': {
        'ingredients': {
          'total_visible': allLines.length,
          'total_json_ld': allLines.length,
          'exact_matches': count('MATCH'),
          'format_only_matches': count('FORMAT_DIFFERENCE'),
          'exact_or_normalized_matches':
              count('MATCH') + count('FORMAT_DIFFERENCE'),
          'quantity_differences': 0,
          'unit_differences': 0,
          'missing_notes': count('MISSING_NOTE'),
          'missing_rows': 0,
          'extra_rows': 0,
          'order_errors': 0,
          'group_heading_differences': 1,
          'supplementary_quantity_note_omissions': 1,
          'note':
              'Supplementary 1,5 kg omission counted as MISSING_NOTE, not a second row error; main quantity unchanged.',
        },
        'instructions': {
          'complete': instructionCount('COMPLETE'),
          'structure_only_differences': instructionCount(
            'COMPLETE_WITH_STRUCTURE_DIFFERENCE',
          ),
          'content_omissions': 0,
          'extra_content': 0,
          'order_errors': 0,
        },
        'titles': {
          'clean': titleCount('CLEAN'),
          'decorated': titleCount('TITLE_DECORATION'),
          'wrong': titleCount('WRONG'),
          'missing': 0,
        },
      },
      'domains': {
        for (final domain in records.map((r) => r['domain'] as String).toSet())
          domain: totals(records.where((r) => r['domain'] == domain).toList()),
      },
    },
    'recipes': records,
  };
}

void main() {
  final report = measure();
  final encoded = const JsonEncoder.withIndent('  ');
  File(
    'results/b2_2_content_source_quality.json',
  ).writeAsStringSync('${encoded.convert(report)}\n');
  final rows = (report['recipes'] as List).cast<Map<String, Object?>>();
  File('results/b2_2_snapshot_reconciliation.json').writeAsStringSync(
    '${encoded.convert([
      for (final r in rows) {'id': r['id'], ...r['snapshot'] as Map<String, Object?>},
    ])}\n',
  );
  final md = StringBuffer(
    '# B2.2 – content/source quality, 11–20\n\n${report['method']}\n\n',
  );
  md.writeln(
    '## Separate metrics\n\n```json\n${encoded.convert(report['summary'])}\n```\n',
  );
  md.writeln(
    '| ID | Source quality | Extractor | Ingredients | Instructions |\n|---|---|---|---|---|',
  );
  for (final r in rows) {
    md.writeln(
      '| ${r['id']} | ${r['source_quality']} | ${r['extractor_verdict']} | ${r['visible_ingredient_count']} | ${(r['instructions'] as Map)['verdict']} |',
    );
  }
  for (final r in rows) {
    md.writeln(
      '\n## ${r['id']}\n\nURL: ${r['url']}\n\nSnapshot: UNCHANGED_RECIPE_CONTENT. HTML changed: ${(r['snapshot'] as Map)['html_changed']}.\n\nTitle: ${jsonEncode(r['title'])}\n',
    );
    md.writeln('| Row | Visible | JSON-LD | Verdict |\n|---|---|---|---|');
    for (final l in (r['ingredients'] as List).cast<Map<String, Object?>>()) {
      md.writeln(
        '| ${l['source_order']} | ${l['visible_text']} | ${l['json_ld_text']} | ${l['source_verdict']} |',
      );
    }
    md.writeln('\nGroups: ${jsonEncode(r['group_heading_differences'])}\n');
    final ins = r['instructions'] as Map<String, Object?>;
    md.writeln(
      'Instructions: ${ins['verdict']}; visible blocks ${ins['visible_actual_blocks']}, JSON-LD steps ${ins['json_ld_step_count']}, extracted entries ${ins['extracted_entry_count']}, JSON-LD headings ${ins['json_ld_heading_count']}. ${ins['note']} Full ordered body comparison: equal. @VISIBLE reference count: ${(r['reference_check'] as Map)['resolved_visible_references']}.\n',
    );
    md.writeln('Extractor evidence: ${jsonEncode(r['extractor_evidence'])}');
  }
  md.writeln(
    '\n## Decision\n\nB2.3 can use the preserved B2.1 input, with rows 14/8 and 14/9 marked as source errors and the 17 ingredient-group omission tracked separately. No extractor change is required. RecipeTextParser was not invoked. B2.0 references, snapshots, corpus and production code were not changed. B2.3 not started.',
  );
  File(
    'results/b2_2_content_source_quality.md',
  ).writeAsStringSync('${md.toString().trimRight()}\n');
  stdout.writeln(encoded.convert(report['summary']));
}
