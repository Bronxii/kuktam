import 'dart:convert';
import 'dart:io';
import 'e2e_simulation.dart';

Map<String, dynamic> read(String file) =>
    jsonDecode(File('results/$file').readAsStringSync())
        as Map<String, dynamic>;

const quantitySourceKeys = {
  '06/2',
  '06/3',
  '06/4',
  '06/9',
  '06/10',
  '07/7',
  '08/2',
  '08/4',
  '08/5',
  '09/3',
  '09/6',
  '09/7',
  '09/8',
  '09/9',
  '10/5',
};

void main() {
  final p1 = read('p1_batch_01-10.json');
  final p3 = read('p3_parser_batch_01-10.json');
  final audit = read('p2_5_source_truth_audit.json');
  final results = <Map<String, Object?>>[];
  final allDiagnostics = <Map<String, Object?>>[];
  final previewDir = Directory('results/p4_previews')
    ..createSync(recursive: true);
  for (var i = 1; i <= 10; i++) {
    final id = i.toString().padLeft(2, '0');
    final source = (p1['results'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((r) => r['id'] == id);
    final candidate =
        (source['candidates'] as List).single as Map<String, dynamic>;
    final simulation = simulate(candidate, source['url'] as String);
    final draft = simulation['draft']! as Map<String, Object?>;
    final ingredients = (draft['ingredients']! as List)
        .cast<Map<String, Object?>>();
    final inputs = (candidate['ingredients'] as List).cast<String>();
    final diagnostics = <Map<String, Object?>>[];
    final corrections = <Map<String, Object?>>[];
    var consistent = ingredients.length == inputs.length;
    for (var j = 0; j < ingredients.length; j++) {
      final row = ingredients[j];
      final prior = (p3['rows'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((r) => r['id'] == id && r['row'] == j + 1);
      final evidence = (audit['decisions'] as List)
          .cast<Map<String, dynamic>>()
          .where(
            (r) =>
                r['id'] == id &&
                r['location'] == 'ingredient ${j + 1}' &&
                r['category'] == 'SOURCE_JSONLD_ERROR',
          )
          .toList();
      final sourceError = evidence.isNotEmpty;
      final unsupported = prior['parser_verdict'] == 'UNSUPPORTED_UNIT';
      final parserError =
          prior['included_in_parser_accuracy'] == true &&
          prior['parser_verdict'] == 'PARSER_ERROR';
      final warnings = row['warnings']! as List<String>;
      consistent =
          consistent &&
          row['rawText'] == inputs[j] &&
          row['name'] == prior['parsed_name'] &&
          row['quantity'] == prior['parsed_quantity'] &&
          row['canonical_unit'] == prior['parsed_canonical_unit'] &&
          jsonEncode(warnings) == jsonEncode(prior['warnings']);
      final notices = <String>[
        ...warnings,
        if (sourceError) 'SOURCE_WARNING',
        if (unsupported) 'UNSUPPORTED_UNIT',
        if (parserError) 'PARSER_WARNING',
      ];
      // Add POC-only provenance metadata; keep parser output and rawText intact.
      row['reviewWarnings'] = notices;
      row['sourceIngredientIndex'] = j;
      if (sourceError) {
        final quantity = quantitySourceKeys.contains('$id/${j + 1}');
        corrections.add({
          'row': j + 1,
          'field': quantity ? 'quantity' : 'name',
          'reason': quantity
              ? 'A forrás mennyisége igazoltan hibás vagy a parserben null lett.'
              : 'A forrás megjegyzést hagyott el; visszaállítása kézi ellenőrzést igényel.',
          'evidence': evidence,
        });
      }
      if (parserError) {
        corrections.add({
          'row': j + 1,
          'field': 'name',
          'reason': 'A db egység a névben maradt a közepes jelző után.',
        });
      }
      final fallback =
          row['canonical_unit'] == 'db' &&
          (unsupported ||
              warnings.contains('missingQuantity') ||
              inputs[j].contains(' közepes db ') ||
              inputs[j].startsWith('0 ízlés szerint'));
      final d = <String, Object?>{
        'id': id,
        'row': j + 1,
        'notices': notices,
        'source_error': sourceError,
        'unsupported_unit': unsupported
            ? (prior['expected_input_interpretation']
                  as Map<String, dynamic>)['unsupported_unit']
            : null,
        'parser_error': parserError,
        'fallback_db': fallback,
        'source_evidence': evidence,
      };
      diagnostics.add(d);
      allDiagnostics.add(d);
    }
    final titleOk = draft['title'] == simulation['normalized_title'];
    final preparationOk =
        draft['preparation'] == simulation['normalized_preparation'];
    final broken =
        !consistent ||
        !titleOk ||
        !preparationOk ||
        (draft['unprocessedSegments']! as List).isNotEmpty;
    final warningRows = diagnostics
        .where((d) => (d['notices']! as List).isNotEmpty)
        .length;
    final affected = corrections.map((c) => c['row']).toSet().length;
    final poor = affected >= 3 && affected * 2 >= ingredients.length;
    final verdict = broken
        ? 'BROKEN'
        : poor
        ? 'POOR'
        : warningRows > 0
        ? 'REVIEW'
        : 'READY';
    final reason = broken
        ? 'A teljes szöveges parse eltér a várt mezőktől; vizsgálat szükséges.'
        : poor
        ? 'Legalább 3 sor és a sorok legalább fele bizonyított mezőjavítást igényel (előre rögzített POC-küszöb).'
        : warningRows > 0
        ? 'A draft teljes, de parser/source/unsupported figyelmeztetés miatt ellenőrzés szükséges.'
        : 'Nincs bizonyított javítandó mező vagy figyelmeztetés.';
    results.add({
      'id': id,
      'url': source['url'],
      ...simulation,
      'diagnostics': diagnostics,
      'verdict': verdict,
      'reason': reason,
      'estimated_manual_corrections_needed': corrections.length,
      'manual_corrections': corrections,
      'manual_review_rows': warningRows,
      'checks': {
        'rows_match_p3': consistent,
        'title_preserved': titleOk,
        'preparation_preserved': preparationOk,
      },
    });
    final preview = StringBuffer('RECEPT: ${draft['title']}\n\nHOZZÁVALÓK:\n');
    for (final r in ingredients) {
      preview.writeln(
        '${r['quantity'] ?? '[JAVÍTANDÓ]'} ${r['canonical_unit']} ${r['name']}',
      );
    }
    preview.writeln(
      '\nWARNING (POC auditjelölések, nem általános automatikus felismerés):',
    );
    for (final d in diagnostics.where(
      (d) => (d['notices']! as List).isNotEmpty,
    )) {
      preview.writeln(
        '${d['row']}. sor: ${(d['notices']! as List).join(', ')}',
      );
    }
    preview.writeln(
      '\nELKÉSZÍTÉS:\n${draft['preparation']}\n\nFŰSZEREK: üres\n\nVERDICT: $verdict\n$reason\nBizonyított mezőjavítás minimum: ${corrections.length}. Az unsupported egységek átváltása nincs találgatva; további user-döntést igényelhet.',
    );
    File(
      '${previewDir.path}/recipe_$id.txt',
    ).writeAsStringSync(preview.toString());
  }
  int count(bool Function(Map<String, Object?>) predicate) =>
      allDiagnostics.where(predicate).length;
  final timing = <String, Object?>{};
  for (final key in [
    'normalization_ms',
    'parser_ms',
    'draft_build_ms',
    'total_local_ms',
  ]) {
    final values = results
        .map((r) => (r['timing']! as Map<String, double>)[key]!)
        .toList();
    timing[key] = {
      'sum': values.fold(0.0, (a, b) => a + b),
      'average': values.fold(0.0, (a, b) => a + b) / 10,
      'max': values.reduce((a, b) => a > b ? a : b),
    };
  }
  final corrections = results.fold(
    0,
    (n, r) => n + (r['estimated_manual_corrections_needed']! as int),
  );
  final summary = {
    'recipes': 10,
    'verdicts': {
      for (final v in ['READY', 'REVIEW', 'POOR', 'BROKEN'])
        v: results.where((r) => r['verdict'] == v).length,
    },
    'total_rows': allDiagnostics.length,
    'clean_rows': count((d) => (d['notices']! as List).isEmpty),
    'warning_rows': count((d) => (d['notices']! as List).isNotEmpty),
    'source_error_rows': count((d) => d['source_error'] == true),
    'unsupported_unit_rows': count((d) => d['unsupported_unit'] != null),
    'parser_error_rows': count((d) => d['parser_error'] == true),
    'invalid_quantity_rows': count(
      (d) => (d['notices']! as List).contains('invalidQuantity'),
    ),
    'unknown_unit_rows': count(
      (d) => (d['notices']! as List).contains('unknownUnit'),
    ),
    'missing_quantity_rows': count(
      (d) => (d['notices']! as List).contains('missingQuantity'),
    ),
    'fallback_db_rows': count((d) => d['fallback_db'] == true),
    'manual_correction_fields_minimum': corrections,
    'manual_corrections_average_per_recipe': corrections / 10,
    'title_suffix_removed_count': results
        .where((r) => r['raw_title'] != r['normalized_title'])
        .length,
    'timing': timing,
  };
  final method = {
    'scope':
        'Offline saved batch 01-10 only; P1/P2/P3 artifacts unchanged. No editor, repository, Firebase, HTTP, AI or save.',
    'normalization':
        'Exact Mindmegette suffix on matching domain only. HowToStep headings joined with text; section entries retained once per input occurrence; HTML text/entities rendered; real line breaks preserved. Raw ingredient lines untouched.',
    'source_warning_provenance':
        'Oracle-assisted: SOURCE_WARNING comes from the already reviewed P2.5 audit, NOT a generic runtime source-error detector. Unsupported/parser notices come from P3 annotations. Without that audit some errors would be silent.',
    'manual_corrections':
        'Lower bound: unique field edits for known source quantity/name errors and supported-input parser name errors. Unknown units and missingQuantity require review but no fabricated conversion/value is counted as mandatory correction.',
    'verdict_policy':
        'BROKEN for pipeline preservation failure; POOR for >=3 rows and >=50% rows needing proven correction; otherwise REVIEW for any notice, READY only without notices. Policy is a transparent POC heuristic, not measured user effort.',
    'timing':
        'Desktop Dart JIT, Stopwatch, single sequential batch with cold first recipe. IO and audit annotation/report generation excluded; draft_build measures parser DTO mapping only. No network time.',
  };
  File('results/p4_e2e_batch_01-10.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'method': method, 'summary': summary, 'results': results})}\n',
  );
  final md = StringBuffer('# P4 – end-to-end POC, batch 01–10\n\n');
  for (final entry in method.entries) {
    md.writeln('**${entry.key}:** ${entry.value}\n');
  }
  md.writeln(
    '```json\n${const JsonEncoder.withIndent('  ').convert(summary)}\n```\n',
  );
  md.writeln(
    '| ID | Verdict | Kötelező mezőjavítás minimum | Normalizálás ms | Parser ms | Draft ms | Lokális összes ms |\n|---|---|---|---|---|---|---|',
  );
  for (final r in results) {
    final t = r['timing']! as Map<String, double>;
    md.writeln(
      '| ${r['id']} | ${r['verdict']} | ${r['estimated_manual_corrections_needed']} | ${t['normalization_ms']} | ${t['parser_ms']} | ${t['draft_build_ms']} | ${t['total_local_ms']} |',
    );
  }
  md.writeln(
    '\nA kategóriák átfednek; warning rows az érintett sorok uniója. A POOR nem adatvesztés: a forrás sok hibája miatt nagy a javítási igény. A címek 5 utótagja eltűnik; 32 lépéscímke 32 saját lépésszöveggel egy sorba kerül. 56 tényleges lépés megmarad. Fűszerbesorolás nincs.\n\n## Preview-k\n',
  );
  for (final r in results) {
    final id = r['id'];
    md.writeln(
      '### $id\n\n```text\n${File('${previewDir.path}/recipe_$id.txt').readAsStringSync()}\n```\n',
    );
  }
  File('results/p4_e2e_batch_01-10.md').writeAsStringSync('${md.toString().trimRight()}\n');
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(summary));
}
