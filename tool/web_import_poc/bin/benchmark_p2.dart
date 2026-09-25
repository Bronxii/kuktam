// Offline P2 measurement only. Does not import the extractor, runner or app.
import 'dart:convert';
import 'dart:io';
import 'package:html/parser.dart' as html;

String normalize(String value) => value
    .replaceAll(
      RegExp(r'[\s\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]+'),
      ' ',
    )
    .trim()
    .toLowerCase();

/// One-to-one text matching: duplicate reference lines cannot be reused.
List<int> matchLines(List<String> expected, List<String> actual) {
  final used = <int>{};
  return [
    for (final line in expected)
      (() {
        for (var j = 0; j < actual.length; j++) {
          if (!used.contains(j) && normalize(line) == normalize(actual[j])) {
            used.add(j);
            return j;
          }
        }
        return -1;
      })(),
  ];
}

Map<String, Object> readGroundTruth(String source) {
  final lines = const LineSplitter().convert(source.replaceFirst('\ufeff', ''));
  final title = lines.indexOf('CÍM:');
  final ingredients = lines.indexOf('HOZZÁVALÓK:');
  final instructions = lines.indexOf('ELKÉSZÍTÉS:');
  if (!(title >= 0 && ingredients > title && instructions > ingredients)) {
    throw const FormatException('Unexpected ground truth sections');
  }
  List<String> range(int a, int b) =>
      lines.sublist(a, b).where((line) => line.trim().isNotEmpty).toList();
  return {
    'title': range(title + 1, ingredients).single,
    'ingredients': range(ingredients + 1, instructions),
    'instructions': range(instructions + 1, lines.length),
  };
}

// Explicit, reviewed correspondences, NOT a semantic similarity algorithm.
// Indices below are 1-based actual source step indices per numbered GT step.
const coverage = <List<List<int>>>[
  [
    [1, 2, 3, 5, 10],
    [4, 5],
    [6, 7],
    [9, 10],
    [10],
    [8, 11],
  ],
  [
    [1],
    [1],
    [2],
    [3],
    [4],
  ],
  [
    [1],
    [2],
    [3, 4],
    [6, 7],
    [5, 7],
  ],
  [
    [1],
    [2],
    [3],
    [4],
    [5],
    [6],
  ],
  [
    [1],
    [2],
    [3],
    [3],
    [3, 4],
    [4],
  ],
  [
    [2],
    [2, 3],
    [3],
    [3],
    [],
  ],
  [
    [1],
    [2],
    [2],
    [3],
  ],
  [
    [1],
    [2],
    [3],
    [4],
    [4, 5],
    [6],
  ],
  [
    [1],
    [2],
    [3, 4],
    [5],
  ],
  [
    [1],
    [2, 3],
    [3, 4],
    [4],
    [5],
    [6, 7],
  ],
];

const differences = <Map<int, String>>[
  {},
  {
    1: 'Hiányzó darált jelző; kevésbé specifikus alapanyag a forrás JSON-LD-ben.',
    8: 'Hiányzó őrölt jelző; kevésbé specifikus alapanyag a forrás JSON-LD-ben.',
  },
  {
    14: 'levesbetét tészta ↔ levelestészta: nem puszta formázás. Forrás/referencia eltérés; automatikus javítás nem indokolt.',
  },
  {},
  {},
  {
    2: '0.5 ↔ 0: valódi mennyiségi eltérés.',
    3: '0.5 ↔ 0: valódi mennyiségi eltérés.',
    4: '0.5 tk ↔ 0 teáskanál: mennyiségi eltérés ÉS eltérő egységmegfogalmazás; nincs unit-konverzió.',
    9: 'A forrás 0 ízlés szerint előtagot ad. A 0 nem tekinthető helyes mennyiségnek.',
    10: 'A forrás 0 ízlés szerint előtagot ad. A 0 nem tekinthető helyes mennyiségnek.',
  },
  {7: '0.5 ↔ 0: valódi mennyiségi eltérés.'},
  {
    2: 'A forrás 0 ízlés szerint előtagot ad. A 0 nem puszta formázás.',
    4: '2.5 ↔ 2: valódi mennyiségi eltérés.',
    5: '2.5 ↔ 2: valódi mennyiségi eltérés.',
  },
  {
    1: 'Kiegészítő forrásszöveg: az eredeti recept bélszínt ír. Nem külön hozzávaló.',
    2: 'Kiegészítő forrásszöveg: ízlés szerint. Nem külön hozzávaló.',
    3: '1.5 ↔ 1: valódi mennyiségi eltérés.',
    6: 'A forrás 0 ízlés szerint előtagot ad.',
    7: 'A forrás 0 ízlés szerint előtagot ad.',
    8: 'A forrás 0 ízlés szerint előtagot ad.',
    9: 'A forrás 0 ízlés szerint előtagot ad.',
  },
  {
    5: '2.5 ↔ 2: valódi mennyiségi eltérés.',
    6: 'Kiegészítő forrásszöveg: langyos. Nem külön hozzávaló.',
  },
];

List<Map<String, dynamic>> sourceRecipes(String source) {
  final recipes = <Map<String, dynamic>>[];
  void visit(Object? node) {
    if (node is Map<String, dynamic>) {
      final type = node['@type'];
      if (type == 'Recipe' || (type is List && type.contains('Recipe'))) {
        recipes.add(node);
      }
      for (final child in node.values) {
        visit(child);
      }
    } else if (node is List) {
      for (final child in node) {
        visit(child);
      }
    }
  }

  for (final script in html.parse(source).querySelectorAll('script')) {
    if (script.attributes['type'] == 'application/ld+json') {
      visit(jsonDecode(script.text));
    }
  }
  return recipes;
}

bool equal(Object? a, Object? b) => jsonEncode(a) == jsonEncode(b);

void main() {
  final poc = Directory.current;
  if (!File('${poc.path}/results/p1_batch_01-10.json').existsSync()) {
    throw StateError('Run from tool/web_import_poc');
  }
  final corpus =
      '${poc.parent.parent.path}/test/fixtures/web_import_corpus/batch_1_01-10';
  final p1 =
      jsonDecode(File('results/p1_batch_01-10.json').readAsStringSync())
          as Map<String, dynamic>;
  final rows = <Map<String, Object?>>[];
  for (var i = 0; i < 10; i++) {
    final id = (i + 1).toString().padLeft(2, '0');
    final result = (p1['results'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((r) => r['id'] == id);
    final candidate =
        (result['candidates'] as List).single as Map<String, dynamic>;
    final gt = readGroundTruth(
      File('$corpus/recipe_$id.txt').readAsStringSync(),
    );
    final expected = gt['ingredients']! as List<String>;
    final actual = (candidate['ingredients'] as List).cast<String>();
    final source = sourceRecipes(
      File('results/${result['html_snapshot']}').readAsStringSync(),
    ).single;
    final raw = source['recipeInstructions'] as List;
    final sourceSteps = raw
        .map(
          (s) =>
              s is String ? s : (s as Map<String, dynamic>)['text'] as String,
        )
        .toList();
    final sourceHeadings = raw
        .whereType<Map<String, dynamic>>()
        .map((s) => s['name'] as String)
        .toList();
    final entries = (candidate['instructions'] as List)
        .cast<Map<String, dynamic>>();
    final actualSteps = entries
        .where((e) => e['kind'] == 'step')
        .map((e) => e['text'])
        .toList();
    final actualHeadings = entries
        .where((e) => e['kind'] == 'heading')
        .map((e) => e['text'])
        .toList();
    final sourceChecks = {
      'name_equal': equal(source['name'], candidate['raw_name']),
      'ingredients_equal': equal(source['recipeIngredient'], actual),
      'raw_instructions_equal': equal(
        source['recipeInstructions'],
        candidate['raw_instructions'],
      ),
      'step_text_and_order_equal': equal(sourceSteps, actualSteps),
      'step_headings_and_order_equal': equal(sourceHeadings, actualHeadings),
    };
    if (sourceChecks.values.any((v) => !v)) {
      throw StateError('$id source fidelity failed');
    }
    // Pairing is reviewed for THIS frozen batch, not inferred by list position.
    if (expected.length != actual.length) {
      throw StateError('$id changed ingredient count');
    }
    final pairs = <Map<String, Object?>>[];
    for (var j = 0; j < expected.length; j++) {
      final normalized = normalize(expected[j]) == normalize(actual[j]);
      final note = differences[i][j + 1];
      if (normalized == (note != null)) {
        throw StateError('$id review stale at ${j + 1}');
      }
      pairs.add({
        'expected_index': j + 1,
        'extracted_index': j + 1,
        'expected': expected[j],
        'extracted': actual[j],
        'category': normalized
            ? (expected[j] == actual[j] ? 'MATCH' : 'FORMAT_DIFFERENCE')
            : 'CONTENT_DIFFERENCE',
        'note': note ?? 'Csak engedélyezett összehasonlítási normalizálás.',
      });
    }
    final matches = matchLines(expected, actual);
    final repeated = <String, List<int>>{};
    for (var j = 0; j < actual.length; j++) {
      repeated.putIfAbsent(normalize(actual[j]), () => []).add(j + 1);
    }
    repeated.removeWhere((key, indexes) => indexes.length < 2);
    final gtSteps = gt['instructions']! as List<String>;
    if (gtSteps.length != coverage[i].length) {
      throw StateError('$id GT steps changed');
    }
    final instructionNotes = <String>[];
    if (i == 0) {
      instructionNotes.add(
        'Négy forráslépés szó szerinti &nbsp; entitást tartalmaz; extractor változatlanul megőrizte.',
      );
    }
    if (i == 5) {
      instructionNotes.add(
        'GT 4: hőkiegyenlítés nincs kifejtve a forrásban; GT 5: nokedli/köret tálalás nincs a JSON-LD-ben. Forrás 3: botmixeres pürésítés szerepel, a tömör GT ezt nem említi. Nem extractorveszteség.',
      );
    }
    if (i == 7) {
      instructionNotes.add(
        'GT 6 ropogós szalonnával tálalása nincs a forrás 6-ban; az csak maradék tejfölt/túrót említ. A szalonna kisütése és félretétele megvan a 2. lépésben. Nem extractorveszteség.',
      );
    }
    if (i == 8) {
      instructionNotes.add(
        'A szalonna felhasználása sem a GT, sem a JSON-LD elkészítésében nincs részletezve; nem extractor által elhagyott lépés.',
      );
    }
    if (i == 9) {
      instructionNotes.add(
        r'A 7. forráslépésben szó szerinti \r\n\r\n karakterlánc van; az output ezt változatlanul őrzi.',
      );
    }
    final decorated =
        normalize(candidate['title'] as String) ==
        '${normalize(gt['title']! as String)} | mindmegette.hu';
    final clean =
        normalize(candidate['title'] as String) ==
        normalize(gt['title']! as String);
    final gaps = i == 5 || i == 7;
    final verdict = differences[i].isNotEmpty || gaps
        ? 'PARTIAL'
        : decorated
        ? 'ACCEPTABLE'
        : 'PERFECT';
    rows.add({
      'id': id,
      'url': result['url'],
      'expected_title': gt['title'],
      'extracted_title': candidate['title'],
      'title_result': decorated
          ? 'TITLE_DECORATION'
          : clean
          ? 'MATCH'
          : 'WRONG_TITLE',
      'title_exact': candidate['title'] == gt['title'],
      'title_normalized_match': clean,
      'expected_ingredient_count': expected.length,
      'extracted_ingredient_count': actual.length,
      'ingredient_exact_match_count': pairs
          .where((p) => p['expected'] == p['extracted'])
          .length,
      'ingredient_match_count': matches.where((m) => m >= 0).length,
      'ingredient_reviewed_correspondences': pairs.length,
      'ingredient_comparison': pairs,
      'missing_ingredients': <String>[],
      'extra_ingredients': <String>[],
      'duplicates': repeated,
      'introduced_duplicate_count': 0,
      'order_status': 'PRESERVED',
      'raw_instruction_count': entries.length,
      'actual_step_count': actualSteps.length,
      'section_heading_count': actualHeadings.length,
      'heading_kind': 'HowToStep.name (nem HowToSection)',
      'how_to_section_count': 0,
      'instruction_completeness_result': gaps
          ? 'MISSING_STEP'
          : actualHeadings.isNotEmpty
          ? 'COMPLETE_WITH_SECTION_HEADINGS'
          : 'COMPLETE',
      'instruction_result_basis':
          'GT-folyamatlefedettség; a MISSING_STEP lehet hiányzó részlet is, nem feltétlen teljes művelet.',
      'instruction_coverage': [
        for (var k = 0; k < gtSteps.length; k++)
          {
            'gt_step': k + 1,
            'gt_text': gtSteps[k],
            'source_steps': coverage[i][k],
            'coverage': (i == 5 && (k == 3 || k == 4)) || (i == 7 && k == 5)
                ? 'PARTIAL_OR_MISSING_DETAIL'
                : 'COVERED',
          },
      ],
      'instruction_notes': instructionNotes,
      'source_actual_steps': actualSteps,
      'lost_steps_by_extractor': 0,
      'duplicated_steps': 0,
      'unexpected_content': <String>[],
      'instruction_order': 'PRESERVED',
      'source_fidelity': sourceChecks,
      'warnings': [
        ...instructionNotes,
        if (differences[i].isNotEmpty)
          'Forrás JSON-LD és GT tartalmi eltérés; nincs automatikus korrekció.',
      ],
      'overall_content_verdict': verdict,
    });
  }
  int sum(String key) => rows.fold(0, (n, r) => n + (r[key]! as int));
  int count(String key, String value) =>
      rows.where((r) => r[key] == value).length;
  final summary = {
    'verdicts': {
      for (final v in ['PERFECT', 'ACCEPTABLE', 'PARTIAL', 'FAILED'])
        v: count('overall_content_verdict', v),
    },
    'content_success_rate_percent':
        100 *
        (count('overall_content_verdict', 'PERFECT') +
            count('overall_content_verdict', 'ACCEPTABLE')) /
        10,
    'title': {
      'clean': count('title_result', 'MATCH'),
      'decorated': count('title_result', 'TITLE_DECORATION'),
      'wrong': count('title_result', 'WRONG_TITLE'),
    },
    'ingredients': {
      'expected': sum('expected_ingredient_count'),
      'extracted': sum('extracted_ingredient_count'),
      'exact_matches': sum('ingredient_exact_match_count'),
      'normalized_matches_including_exact': sum('ingredient_match_count'),
      'reviewed_correspondences_not_accuracy': 100,
      'content_difference_pairs': 21,
      'missing_whole_lines': 0,
      'extra_whole_lines': 0,
      'duplicate_occurrences': 1,
      'introduced_duplicates': 0,
      'order_preserved_percent': 100,
    },
    'instructions': {
      'raw_entries': sum('raw_instruction_count'),
      'actual_steps': sum('actual_step_count'),
      'step_headings': sum('section_heading_count'),
      'how_to_sections': 0,
      'complete': count('instruction_completeness_result', 'COMPLETE'),
      'complete_with_section_headings': count(
        'instruction_completeness_result',
        'COMPLETE_WITH_SECTION_HEADINGS',
      ),
      'missing_step_or_detail_relative_gt': 2,
      'extra_content': 0,
      'order_error': 0,
      'lost_steps_by_extractor': 0,
      'duplicated_steps': 0,
    },
    'source_json_ld_fidelity_cases': 10,
  };
  File('results/p2_batch_01-10.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'phase': 'P2', 'method': 'Offline frozen P1 and HTML JSON-LD audit + GT. Exact/normalized matching is automated. Semantic correspondences and process coverage explicitly reviewed; no similarity percentage for paraphrased instructions. No network, parser or unit parsing/conversion.', 'dataset_path': Directory(corpus).absolute.path, 'inputs': 'p1_batch_01-10.json, html/p1_01.html..p1_10.html, recipe_01.txt..recipe_10.txt', 'summary': summary, 'results': rows})}\n',
  );
  final md = StringBuffer('# P2 – batch 01–10, offline tartalmi audit\n\n');
  md.writeln(
    'Csak mentett P1 JSON + HTML JSON-LD és a 10 referencia. Nincs hálózat, parser, konverzió vagy extractor-módosítás. A szemantikus megfeleltetés dokumentált szöveges audit, nem automatikus hasonlósági mérés.\n',
  );
  md.writeln(
    '| ID | Cím | Verdict | Hozzávaló GT/ki | Exact/normalizált | Nyers/lépés/címke | Elkészítés |',
  );
  md.writeln('|---|---|---|---|---|---|---|');
  for (final r in rows) {
    md.writeln(
      '| ${r['id']} | ${(r['extracted_title'] as String).replaceAll('|', r'\|')} | ${r['overall_content_verdict']} | ${r['expected_ingredient_count']}/${r['extracted_ingredient_count']} | ${r['ingredient_exact_match_count']}/${r['ingredient_match_count']} | ${r['raw_instruction_count']}/${r['actual_step_count']}/${r['section_heading_count']} | ${r['instruction_completeness_result']} |',
    );
  }
  md.writeln(
    '\nÖsszesítés:\n```json\n${const JsonEncoder.withIndent('  ').convert(summary)}\n```\n',
  );
  md.writeln(
    'A 100/100 hozzávaló-megfeleltetés NEM 100% pontosság: 21 sorban tartalmi eltérés van. Hiány/extra itt teljes sor hiányát jelenti; a hiányzó jelzőket és eltérő mennyiségeket külön számláljuk. Azonos nevű, eltérő mennyiségű hozzávalókat nem deduplikálunk. Az 05 két vaníliáscukor-sora a GT-ben és a forrásban is szerepel, nem új duplikáció.\n',
  );
  md.writeln(
    'Minden nyers ingredients és instructions adat egyezik a mentett HTML JSON-LD-jével. Az 56 valódi lépés és 32 lépéscímke szövege/sorrendje veszteségmentes. A 32 címke HowToStep.name, nem 32 valódi receptszakasz. A két MISSING_STEP minősítés GT-hez képesti részlethiány, nem extractor által elhagyott lépés.\n',
  );
  for (final r in rows) {
    md.writeln(
      '## ${r['id']} – ${r['overall_content_verdict']}\n\nURL: ${r['url']}\n\nCím: ${r['title_result']}. Hozzávalósorrend: ${r['order_status']}. Teljes hiányzó/extra sor: 0/0. Új duplikáció: 0.\n',
    );
    for (final pair
        in (r['ingredient_comparison']! as List<Map<String, Object?>>).where(
          (p) => p['category'] == 'CONTENT_DIFFERENCE',
        )) {
      md.writeln(
        '- Sor ${pair['expected_index']}: `${pair['expected']}` → `${pair['extracted']}`. ${pair['note']}',
      );
    }
    md.writeln('\nGT-lépés → kinyert valódi lépések (1-alapú):\n');
    for (final c in r['instruction_coverage']! as List<Map<String, Object>>) {
      md.writeln('- ${c['gt_step']} → ${c['source_steps']}: ${c['coverage']}');
    }
    for (final note in r['instruction_notes']! as List<String>) {
      md.writeln('- $note');
    }
    md.writeln();
  }
  md.writeln(
    '## Következtetés és javaslat (nem implementálva)\n\nA technikai 10/10 siker nem azonos a tartalmi sikerrel (3/10). A forrás JSON-LD már tartalmazza a 8 mennyiségi eltérést, 7 nullás ízlés szerinti előtagot, 2 hiányzó jelzőt, 1 eltérő tésztanevet és 3 kiegészítő megjegyzést. Ezek nem extractor által okozott adatveszteségek.\n\nP3 előtt nem indokolt átírni a nyers extractort. A későbbi normalizáló/prezentációs rétegben külön kezelhető a pontos webhely-utótag, a lépéscímke, a HTML-entitás és a literális sortörés. A hibás/nullás mennyiséget tilos találgatással javítani; forrásminőségi figyelmeztetés és felhasználói ellenőrzés szükséges. P3 majd külön engedéllyel indulhat, a forráshibákat a parser hibáitól elválasztva.',
  );
  File('results/p2_batch_01-10.md').writeAsStringSync(md.toString());
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(summary));
}
