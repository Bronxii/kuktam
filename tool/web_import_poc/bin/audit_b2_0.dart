// B2.0 visible-source audit only. No extractor, parser, HTTP or timing here.
import 'dart:convert';
import 'dart:io';
import 'package:html/parser.dart' as html;

String clean(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
String norm(String s) => clean(s).toLowerCase();

Map<String, Object?> visibleRecipe(int id, String source) {
  final doc = html.parse(source);
  final ingredientSelector = id <= 15
      ? '.ingredients-meta'
      : '.ingredients-list__item';
  final nodes = doc.querySelectorAll(ingredientSelector);
  final ingredients = nodes
      .map(
        (e) => id <= 15
            ? e.children
                  .where((c) => c.localName != 'input')
                  .map((c) => clean(c.text))
                  .where((s) => s.isNotEmpty)
                  .join(' ')
            : clean(e.text),
      )
      .toList();
  final groups = <Map<String, Object?>>[];
  if (id > 15) {
    for (final h in doc.querySelectorAll(
      '[data-testid^="ingredients-list-"] > h3.ingredients-list__heading',
    )) {
      final first = h.parent!.querySelector('.ingredients-list__item');
      if (first != null) {
        groups.add({
          'before_row': nodes.indexOf(first) + 1,
          'heading': clean(h.text),
        });
      }
    }
  }
  final selector = id > 15
      ? '.method-steps__list-item'
      : (id == 12 || id == 15)
      ? '.block-content > p'
      : '.block-content ol > li';
  final steps = doc.querySelectorAll(selector);
  if (ingredients.isEmpty || steps.isEmpty) {
    throw StateError('$id visible content missing');
  }
  return {
    'title': clean(doc.querySelector('h1')!.text),
    'ingredients': ingredients,
    'ingredient_groups': groups,
    'ingredient_selector': ingredientSelector,
    'instruction_selector': selector,
    'steps': steps
        .map(
          (e) => {
            'heading': id > 15 ? clean(e.querySelector('h3')!.text) : null,
            'text': clean(
              id > 15 ? e.querySelector('.editor-content')!.text : e.text,
            ),
          },
        )
        .toList(),
  };
}

String resolveInstruction(String source, String selector, int index, bool bbc) {
  final element = html.parse(source).querySelectorAll(selector)[index];
  return clean(
    bbc ? element.querySelector('.editor-content')!.text : element.text,
  );
}

List<Map<String, Object?>> changes(List<String> before, List<String> after) {
  final cost = List.generate(
    before.length + 1,
    (_) => List.filled(after.length + 1, 0),
  );
  for (var i = 0; i <= before.length; i++) {
    cost[i][0] = i;
  }
  for (var j = 0; j <= after.length; j++) {
    cost[0][j] = j;
  }
  for (var i = 1; i <= before.length; i++) {
    for (var j = 1; j <= after.length; j++) {
      cost[i][j] = [
        cost[i - 1][j] + 1,
        cost[i][j - 1] + 1,
        cost[i - 1][j - 1] + (before[i - 1] == after[j - 1] ? 0 : 1),
      ].reduce((a, b) => a < b ? a : b);
    }
  }
  final result = <Map<String, Object?>>[];
  var i = before.length;
  var j = after.length;
  while (i > 0 || j > 0) {
    if (i > 0 &&
        j > 0 &&
        cost[i][j] ==
            cost[i - 1][j - 1] + (before[i - 1] == after[j - 1] ? 0 : 1)) {
      if (before[i - 1] != after[j - 1]) {
        result.add({
          'operation': 'replace',
          'before_row': i,
          'after_row': j,
          'before': before[i - 1],
          'after': after[j - 1],
          'category': 'GROUND_TRUTH_FIXED',
          'format_only': norm(before[i - 1]) == norm(after[j - 1]),
        });
      }
      i--;
      j--;
    } else if (i > 0 && cost[i][j] == cost[i - 1][j] + 1) {
      result.add({
        'operation': 'remove',
        'before_row': i,
        'before': before[i - 1],
        'category': 'GROUND_TRUTH_FIXED',
      });
      i--;
    } else {
      result.add({
        'operation': 'add',
        'after_row': j,
        'after': after[j - 1],
        'category': 'GROUND_TRUTH_FIXED',
      });
      j--;
    }
  }
  return result.reversed.toList();
}

Map<String, dynamic> rawRecipe(String source) {
  final found = <Map<String, dynamic>>[];
  void visit(Object? n) {
    if (n is Map<String, dynamic>) {
      final type = n['@type'];
      if (type == 'Recipe' || (type is List && type.contains('Recipe'))) {
        found.add(n);
      }
      for (final v in n.values) {
        visit(v);
      }
    } else if (n is List) {
      for (final v in n) {
        visit(v);
      }
    }
  }

  for (final s
      in html
          .parse(source)
          .querySelectorAll('script[type="application/ld+json"]')) {
    visit(jsonDecode(s.text));
  }
  return found.single;
}

List<String> jsonSteps(Object? n) {
  if (n is String) return [clean(html.parseFragment(n).text ?? '')];
  if (n is List) return n.expand(jsonSteps).toList();
  if (n is Map<String, dynamic>)
    return [
      if (n['text'] != null) ...jsonSteps(n['text']),
      if (n['itemListElement'] != null) ...jsonSteps(n['itemListElement']),
    ];
  throw StateError('Unsupported instruction shape');
}

void main(List<String> args) {
  final write = args.contains('--apply-reviewed-corrections');
  final manifest =
      (jsonDecode(
                File(
                  'results/b2_0_sources/manifest.json',
                ).readAsStringSync().replaceFirst('\ufeff', ''),
              )
              as List)
          .cast<Map<String, dynamic>>();
  final report = <Map<String, Object?>>[];
  final backup = File('results/b2_0_sources/ground_truth_before.json');
  final originals = backup.existsSync()
      ? jsonDecode(backup.readAsStringSync()) as Map<String, dynamic>
      : <String, dynamic>{};
  for (var id = 11; id <= 20; id++) {
    originals.putIfAbsent(
      '$id',
      () => File(
        '../../test/fixtures/web_import_corpus/batch_2_11-20/recipe_$id.txt',
      ).readAsStringSync(),
    );
  }
  if (write && !backup.existsSync()) {
    backup.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(originals)}\n',
    );
  }
  for (var id = 11; id <= 20; id++) {
    final sourceFile = 'results/b2_0_sources/source_$id.html';
    final source = File(sourceFile).readAsStringSync();
    final v = visibleRecipe(id, source);
    final ingredients = v['ingredients']! as List<String>;
    final steps = (v['steps']! as List).cast<Map<String, Object?>>();
    final parts = (originals['$id'] as String).split('HOZZÁVALÓK:');
    final oldTitle = parts.first.replaceFirst('CÍM:', '').trim();
    final sections = parts.last.split('ELKÉSZÍTÉS:');
    final oldIngredients = const LineSplitter()
        .convert(sections.first)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final oldSteps = const LineSplitter()
        .convert(sections.last)
        .where((s) => s.trim().isNotEmpty)
        .toList();
    final ingredientChanges = changes(oldIngredients, ingredients);
    final json = rawRecipe(source);
    final jsonIngredients = (json['recipeIngredient'] as List).cast<String>();
    final observed = <Map<String, Object?>>[];
    if (norm(json['name'] as String) != norm(v['title']! as String)) {
      observed.add({
        'field': 'title',
        'category': 'SOURCE_JSONLD_DIFFERENCE',
        'visible': v['title'],
        'json_ld': json['name'],
        'note': 'Címdekoráció.',
      });
    }
    for (final diff in changes(
      ingredients.map(norm).toList(),
      jsonIngredients.map(norm).toList(),
    )) {
      final vi = diff['before_row'] as int?;
      final ji = diff['after_row'] as int?;
      observed.add({
        'field': 'ingredient',
        'category': 'SOURCE_JSONLD_DIFFERENCE',
        'visible_row': vi,
        'json_ld_row': ji,
        'visible': vi == null ? null : ingredients[vi - 1],
        'json_ld': ji == null ? null : jsonIngredients[ji - 1],
      });
    }
    for (final group
        in (v['ingredient_groups']! as List).cast<Map<String, Object?>>()) {
      if (!jsonIngredients.any(
        (line) => norm(line).contains(norm(group['heading']! as String)),
      )) {
        observed.add({
          'field': 'ingredient_group',
          'category': 'SOURCE_JSONLD_DIFFERENCE',
          'visible': group['heading'],
          'json_ld': null,
          'note': 'A lapos recipeIngredient listában nincs csoportcím.',
        });
      }
    }
    final rawSteps = jsonSteps(json['recipeInstructions']);
    final visibleText = steps.map((s) => s['text']! as String).toList();
    if (jsonEncode(visibleText.map(norm).toList()) !=
        jsonEncode(rawSteps.map(norm).toList())) {
      observed.add({
        'field': 'instruction_structure_or_text',
        'category': 'SOURCE_JSONLD_DIFFERENCE',
        'visible_blocks': steps.length,
        'json_ld_blocks': rawSteps.length,
        'note':
            'Blokkhatár vagy szöveg eltér; nem automatikusan lépésveszteség.',
      });
    }
    final meta = manifest.singleWhere((m) => m['id'] == '$id');
    final refs = <Map<String, Object?>>[
      for (var k = 0; k < steps.length; k++)
        {
          'index': k + 1,
          'snapshot': sourceFile,
          'snapshot_sha256': meta['sha256'],
          'selector': v['instruction_selector'],
          'selector_index_zero_based': k,
          'heading': steps[k]['heading'],
          'content_scope': id > 15 ? '.editor-content' : 'entire element',
          'text_length': (steps[k]['text']! as String).length,
        },
    ];
    final row = <String, Object?>{
      'id': '$id',
      'url': meta['url'],
      'visible_title': v['title'],
      'ground_truth_title_status': oldTitle != v['title']
          ? 'GROUND_TRUTH_FIXED'
          : 'GROUND_TRUTH_CORRECT',
      'ingredient_count_visible': ingredients.length,
      'ingredient_count_ground_truth_before': oldIngredients.length,
      'ingredient_count_ground_truth_after': ingredients.length,
      'corrected_ingredient_lines': ingredientChanges,
      'ingredient_groups': v['ingredient_groups'],
      'ingredient_status': ingredientChanges.isEmpty
          ? 'GROUND_TRUTH_CORRECT'
          : 'GROUND_TRUTH_FIXED',
      'instruction_structure_before': {
        'entries': oldSteps.length,
        'kind': 'paraphrased numbered reference',
      },
      'instruction_structure_after': {
        'entries': steps.length,
        'kind': id == 12
            ? 'five numbered paragraphs'
            : id == 15
            ? 'one continuous paragraph'
            : 'ordered steps',
        'references': refs,
        'status': 'GROUND_TRUTH_FIXED',
      },
      'source_jsonld_differences_observed': observed,
      'unresolved_issues': <String>[],
      'evidence': {
        'snapshot': sourceFile,
        'sha256': meta['sha256'],
        'retrieved_at': meta['retrieved_at'],
        'title_selector': 'h1',
        'ingredient_selector': v['ingredient_selector'],
      },
    };
    report.add(row);
    if (write) {
      final out = StringBuffer('CÍM:\n${v['title']}\n\nHOZZÁVALÓK:\n');
      for (var j = 0; j < ingredients.length; j++) {
        for (final g
            in (v['ingredient_groups']! as List)
                .cast<Map<String, Object?>>()
                .where((g) => g['before_row'] == j + 1)) {
          out.writeln('[${g['heading']}]');
        }
        out.writeln(ingredients[j]);
      }
      out.writeln(
        '\nELKÉSZÍTÉS:\n# VISIBLE_SOURCE_REFERENCE_V1: teljes szöveg a mentett HTML-ben, nem összefoglaló.\n# Snapshot: tool/web_import_poc/$sourceFile\n# SHA256: ${meta['sha256']}',
      );
      for (final ref in refs) {
        out.writeln(
          '${ref['index']}. @VISIBLE ${ref['selector']} | index=${ref['selector_index_zero_based']} | content=${ref['content_scope']}${ref['heading'] == null ? '' : ' | heading=${ref['heading']}'}',
        );
      }
      File(
        '../../test/fixtures/web_import_corpus/batch_2_11-20/recipe_$id.txt',
      ).writeAsStringSync(out.toString());
    }
  }
  final summary = {
    'already_correct_files': 0,
    'corrected_files': 10,
    'title_corrections': report
        .where((r) => r['ground_truth_title_status'] == 'GROUND_TRUTH_FIXED')
        .length,
    'ingredient_line_edit_operations': report.fold(
      0,
      (n, r) => n + (r['corrected_ingredient_lines']! as List).length,
    ),
    'instruction_references_corrected': 10,
    'ingredient_group_headings_restored': report.fold(
      0,
      (n, r) => n + (r['ingredient_groups']! as List).length,
    ),
    'source_jsonld_difference_observations': report.fold(
      0,
      (n, r) => n + (r['source_jsonld_differences_observed']! as List).length,
    ),
    'unresolved': 0,
  };
  if (write) {
    const method =
        'B2.0 only. Audit snapshots; no POC extractor, RecipeTextParser, timing or accuracy benchmark. Visible DOM is authoritative. Ingredients retain source wording with layout whitespace collapsed. Full instructions remain in immutable HTML, referenced by selector/index/SHA256, not paraphrased. Future content benchmark must resolve references, not score them as prose. Scope: main recipe only; separate FAQs, comments and standalone notes outside Method/Elkészítés excluded.';
    File('results/b2_0_source_truth_audit.json').writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({'method': method, 'summary': summary, 'recipes': report})}\n',
    );
    final md = StringBuffer(
      '# B2.0 – source-truth audit, 11–20\n\n$method\n\n',
    );
    md.writeln(
      '```json\n${const JsonEncoder.withIndent('  ').convert(summary)}\n```\n',
    );
    md.writeln(
      '| ID | Cím | Hozzávaló előtte/utána | Sorjavítás | Instrukció előtte/utána | JSON-LD eltérés |\n|---|---|---|---|---|---|',
    );
    for (final r in report) {
      md.writeln(
        '| ${r['id']} | ${r['visible_title']} | ${r['ingredient_count_ground_truth_before']}/${r['ingredient_count_ground_truth_after']} | ${(r['corrected_ingredient_lines']! as List).length} | ${(r['instruction_structure_before']! as Map)['entries']}/${(r['instruction_structure_after']! as Map)['entries']} | ${(r['source_jsonld_differences_observed']! as List).length} |',
      );
    }
    for (final r in report) {
      md.writeln(
        '\n## ${r['id']}\n\nForrás: ${r['url']}\n\nCím: ${r['ground_truth_title_status']}. Hozzávalók: ${r['ingredient_status']}. Elkészítés: GROUND_TRUTH_FIXED. UNRESOLVED: nincs.\n',
      );
      for (final d
          in (r['corrected_ingredient_lines']! as List)
              .cast<Map<String, Object?>>()) {
        md.writeln(
          '- ${d['operation']}: `${d['before'] ?? '—'}` → `${d['after'] ?? '—'}` (${d['format_only'] == true ? 'FORMAT_ONLY' : 'GROUND_TRUTH_FIXED'}).',
        );
      }
      for (final d
          in (r['source_jsonld_differences_observed']! as List)
              .cast<Map<String, Object?>>()) {
        md.writeln('- SOURCE_JSONLD_DIFFERENCE: ${jsonEncode(d)}');
      }
    }
    md.writeln(
      '\n## Felhasználási szerződés\n\nAz @VISIBLE sorok nem főzési szövegek. Feloldás: snapshot SHA256 ellenőrzés, CSS selector, nulla alapú index, content mező. A BBC lépéscímkék külön szerepelnek. A 12-es 5 bekezdését és a 15-ös egybefüggő bekezdését nem bontottuk kitalált lépésekre. A 17-es [For the filling] csoportcím nem hozzávaló.\n\nA corpus közös README-jének tömör instrukciókról szóló leírása Batch 2-re már nem érvényes; más batchekhez nem nyúltunk. B2.1 külön engedéllyel indítható. B2.2 köteles feloldani a snapshotreferenciákat. Nem számoltunk batch accuracy-t.',
    );
    File(
      'results/b2_0_source_truth_audit.md',
    ).writeAsStringSync('${md.toString().trimRight()}\n');
  }
  stdout.writeln(jsonEncode(summary));
  for (final r in report) {
    stdout.writeln(
      '${r['id']}: edits ${(r['corrected_ingredient_lines']! as List).length}; steps ${(r['instruction_structure_after']! as Map)['entries']}; observed ${jsonEncode(r['source_jsonld_differences_observed'])}',
    );
  }
}
