// Offline snapshot inspection for P2.5 only; not a web extractor/fallback.
import 'dart:convert';
import 'dart:io';
import 'package:html/parser.dart' as html;
import 'benchmark_p2.dart' as p2;

String text(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

void main(List<String> args) {
  if (!args.contains('--write-reviewed-results')) {
    throw ArgumentError(
      'Explicit --write-reviewed-results required (offline).',
    );
  }
  final p1 =
      jsonDecode(File('results/p1_batch_01-10.json').readAsStringSync())
          as Map<String, dynamic>;
  final old =
      jsonDecode(File('results/p2_batch_01-10.json').readAsStringSync())
          as Map<String, dynamic>;
  final audit = <Map<String, Object?>>[];
  final corrected = <Map<String, Object?>>[];
  final changes = <Map<String, Object?>>[];
  for (var i = 1; i <= 10; i++) {
    final id = i.toString().padLeft(2, '0');
    final r = (p1['results'] as List).cast<Map<String, dynamic>>().singleWhere(
      (e) => e['id'] == id,
    );
    final prior = (old['results'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((e) => e['id'] == id);
    final c = (r['candidates'] as List).single as Map<String, dynamic>;
    final doc = html.parse(File('results/html/p1_$id.html').readAsStringSync());
    final nodes = doc.querySelectorAll(
      i <= 5 ? '.ingredients-meta' : '#ingredients li.m-list__item',
    );
    final visible = nodes
        .map(
          (e) => i <= 5
              ? e.children
                    .where((child) => child.localName != 'input')
                    .map((child) => text(child.text))
                    .where((s) => s.isNotEmpty)
                    .join(' ')
              : text(e.text),
        )
        .toList();
    final actual = (c['ingredients'] as List).cast<String>();
    if (visible.length != actual.length) {
      throw StateError('$id ingredient evidence count');
    }
    final gtFile = File(
      '../../test/fixtures/web_import_corpus/batch_1_01-10/recipe_$id.txt',
    );
    final gt = p2.readGroundTruth(gtFile.readAsStringSync());
    final gtIngredients = List<String>.from(gt['ingredients']! as List<String>);
    var gtInstructions = List<String>.from(gt['instructions']! as List<String>);
    final source = p2
        .sourceRecipes(File('results/html/p1_$id.html').readAsStringSync())
        .single;
    final entries = (c['instructions'] as List).cast<Map<String, dynamic>>();
    final steps = entries
        .where((e) => e['kind'] == 'step')
        .map((e) => e['text'] as String)
        .toList();
    final sourceSteps = (source['recipeInstructions'] as List)
        .map(
          (e) =>
              e is String ? e : (e as Map<String, dynamic>)['text'] as String,
        )
        .toList();
    if (!p2.equal(source['recipeIngredient'], actual) ||
        !p2.equal(sourceSteps, steps)) {
      throw StateError('$id extraction fidelity');
    }
    final visibleSteps = i <= 5
        ? doc
              .querySelectorAll('ol')
              .singleWhere(
                (e) =>
                    e.children.isNotEmpty &&
                    text(e.children.first.text) ==
                        text(html.parseFragment(steps.first).text ?? ''),
              )
              .children
              .map((e) => text(e.text))
              .toList()
        : doc
              .querySelectorAll('.p-recipe__directions li')
              .map((e) => text(e.text))
              .toList();
    if (visibleSteps.length != steps.length) {
      throw StateError('$id visible steps evidence');
    }
    // Audit equality only: ignore rendered whitespace/entity spelling, never
    // rewrite extraction output or use this as a production normalization rule.
    for (var j = 0; j < steps.length; j++) {
      final rendered = html.parseFragment(steps[j]).text ?? '';
      if (rendered.replaceAll(RegExp(r'\s+'), '') !=
          visibleSteps[j].replaceAll(RegExp(r'\s+'), '')) {
        throw StateError('$id visible instruction ${j + 1} content differs');
      }
    }
    void add(
      String location,
      String category,
      Object? v,
      Object? json,
      Object? ground,
      String why, {
      bool incidental = false,
    }) {
      audit.add({
        'id': id,
        'url': r['url'],
        'snapshot': r['html_snapshot'],
        'location': location,
        'category': category,
        'visible_page_value': v,
        'json_ld_value': json,
        'ground_truth_value': ground,
        'evidence': why,
        'incidental': incidental,
      });
    }

    final originalPairs = (prior['ingredient_comparison'] as List)
        .cast<Map<String, dynamic>>();
    final problemIndexes = <int>{};
    for (final pair in originalPairs.where(
      (p) => p['category'] == 'CONTENT_DIFFERENCE',
    )) {
      final n = (pair['expected_index'] as int) - 1;
      problemIndexes.add(n);
      final gtError =
          (i == 3 && n == 13) ||
          (i == 9 && (n == 0 || n == 1)) ||
          (i == 10 && n == 5);
      final reason = gtError
          ? 'A látható recept és a JSON-LD azonos információt ad; a referencia átírta a nevet vagy kihagyta a megjegyzést.'
          : i == 2
          ? 'A .ingredients-meta small elemben a jelző látható, de a JSON-LD kihagyja.'
          : 'A #ingredients listában a tört mennyiség / mennyiség nélküli ízlés szerint helyes; a JSON-LD csonkol vagy 0 előtagot illeszt be.';
      add(
        'ingredient ${n + 1}',
        gtError ? 'GROUND_TRUTH_ERROR' : 'SOURCE_JSONLD_ERROR',
        visible[n],
        actual[n],
        pair['expected'],
        reason,
      );
      if (gtError) {
        changes.add({
          'id': id,
          'location': 'ingredient ${n + 1}',
          'before': pair['expected'],
          'after': visible[n],
        });
        gtIngredients[n] = visible[n];
      }
    }
    // Incidental omissions observed in the same inspected lists. Do not silently
    // score these as correct just because both old GT and JSON-LD omitted them.
    final incidental = i == 2
        ? [2]
        : i == 3
        ? [2, 3, 6, 7]
        : <int>[];
    for (final n in incidental) {
      add(
        'ingredient ${n + 1}',
        'SOURCE_JSONLD_ERROR',
        visible[n],
        actual[n],
        originalPairs[n]['expected'],
        'További látható zárójeles megjegyzés hiányzik a JSON-LD-ből és a régi GT-ből is. Külön, járulékos találat; GT itt nem módosult.',
        incidental: true,
      );
    }
    if (i == 6 || i == 8) {
      final before = (prior['instruction_coverage'] as List)
          .cast<Map<String, dynamic>>()
          .map((e) => e['gt_text'])
          .toList();
      add(
        'instructions',
        'GROUND_TRUTH_ERROR',
        visibleSteps,
        steps,
        before,
        i == 6
            ? 'A látható 3 lépés egyezik a JSON-LD-vel; nincs hőkiegyenlítés/köret-tálalás, van botmixerezés. A referencia hozzáírt és elhagyott részleteket.'
            : 'A látható 6 lépés egyezik a JSON-LD-vel; a tálalás tejfölt/túrót említ, nem szalonnát. A weboldalt nem javítjuk főzési tudásból.',
      );
      gtInstructions = [
        for (var j = 0; j < visibleSteps.length; j++)
          '${j + 1}. ${visibleSteps[j]}',
      ];
      changes.add({
        'id': id,
        'location': 'instructions',
        'before': before,
        'after': gtInstructions,
      });
    }
    if (i <= 5) {
      final heading = doc.querySelector('h1');
      if (heading == null) {
        throw StateError('Missing h1 $id');
      }
      add(
        'title',
        'FORMAT_DIFFERENCE',
        text(heading.text),
        c['title'],
        gt['title'],
        'A látható h1 receptcímhez a JSON-LD webhely-utótagot ad.',
      );
    }
    for (var j = 0; j < steps.length; j++) {
      if (steps[j].contains('&nbsp;') ||
          steps[j].contains(r'\r\n') ||
          steps[j].contains('\r\n')) {
        add(
          'instruction ${j + 1} markup',
          'FORMAT_DIFFERENCE',
          visibleSteps[j],
          steps[j],
          (prior['instruction_coverage'] as List)
              .map((e) => (e as Map<String, dynamic>)['gt_text'])
              .toList(),
          i == 10
              ? 'A dekódolt JSON-LD valódi CR/LF sortörést tartalmaz, nem literális backslash-r/backslash-n karaktereket. A P2 korábbi megfogalmazása pontatlan volt. Nincs tartalomveszteség.'
              : 'A látható HTML whitespace-ként jeleníti meg az &nbsp; entitást; a JSON-LD-ben entitásszöveg marad. Nincs tartalomveszteség.',
        );
      }
    }
    if (changes.any((e) => e['id'] == id)) {
      gtFile.writeAsStringSync(
        'CÍM:\n${gt['title']}\n\nHOZZÁVALÓK:\n${gtIngredients.join('\n')}\n\nELKÉSZÍTÉS:\n${gtInstructions.join('\n')}\n',
      );
    }
    final sourceErrors = audit
        .where((e) => e['id'] == id && e['category'] == 'SOURCE_JSONLD_ERROR')
        .length;
    final comparison = p2.matchLines(gtIngredients, actual);
    corrected.add({
      'id': id,
      'url': r['url'],
      'title': c['title'],
      'expected_ingredients': gtIngredients,
      'extracted_ingredients': actual,
      'normalized_match_count': comparison.where((n) => n >= 0).length,
      'source_ingredient_mismatches': sourceErrors,
      'source_quantity_mismatches': i >= 6
          ? problemIndexes
                .where(
                  (n) =>
                      !((i == 9 && (n == 0 || n == 1)) || (i == 10 && n == 5)),
                )
                .length
          : 0,
      'source_instruction_omissions': 0,
      'raw_instruction_entries': entries.length,
      'actual_steps': steps.length,
      'step_headings': entries.length - steps.length,
      'extractor': {
        'rows_lost': 0,
        'rows_added': 0,
        'order_errors': 0,
        'instruction_loss': 0,
      },
      'visible_instructions': visibleSteps,
      'verdict': sourceErrors > 0
          ? 'PARTIAL'
          : i <= 5
          ? 'ACCEPTABLE'
          : 'PERFECT',
      'verdict_basis':
          'Visible snapshot vs JSON-LD, including explicitly listed incidental omissions. Strict GT string equality is NOT the verdict.',
    });
  }
  final categories = <String, int>{};
  for (final e in audit.where((e) => e['incidental'] == false)) {
    categories.update(
      e['category']! as String,
      (n) => n + 1,
      ifAbsent: () => 1,
    );
  }
  final summary = <String, Object?>{
    'primary_audit_decisions': categories,
    'incidental_source_errors': 5,
    'counting_unit':
        'One ingredient row, one complete instruction-reference correction per recipe, one title per recipe, one markup-bearing step.',
    'corrected_files': changes
        .map((e) => 'recipe_${e['id']}.txt')
        .toSet()
        .toList(),
    'extractor': {
      'ingredients_preserved': 100,
      'ingredients_total': 100,
      'steps_preserved': 56,
      'steps_total': 56,
      'rows_lost': 0,
      'rows_added': 0,
      'order_errors': 0,
      'instruction_loss': 0,
      'fidelity_percent': 100,
    },
    'source_quality': {
      'ingredient_mismatches': 22,
      'ingredient_rows_total': 100,
      'ingredient_content_agreement_percent': 78,
      'quantity_mismatches': 15,
      'truncated_fraction_rows': 8,
      'spurious_zero_rows': 7,
      'instruction_omissions': 0,
      'title_decoration_only': 5,
    },
    'verdicts': {
      for (final v in ['PERFECT', 'ACCEPTABLE', 'PARTIAL', 'FAILED'])
        v: corrected.where((r) => r['verdict'] == v).length,
    },
    'scope_note':
        'Primary 21 ingredients + 06/08 instructions + titles/markup. Five incidental ingredient-note omissions are separately disclosed and included in source-quality verdict. Other GT instructions remain paraphrased; no literal instruction accuracy is claimed.',
  };
  void save(String name, Object value) => File(
    'results/$name.json',
  ).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(value)}\n');
  save('p2_5_source_truth_audit', {
    'method':
        'Offline saved visible HTML nodes vs JSON-LD vs frozen original P2 GT; no HTTP, AI service, parser or extractor modification. DOM selectors are audit evidence only, not a fallback pipeline.',
    'summary': summary,
    'decisions': audit,
    'ground_truth_changes': changes,
  });
  save('p2_corrected_batch_01-10', {'summary': summary, 'results': corrected});
  final md = StringBuffer(
    '# P2.5 source-truth audit\n\nCsak mentett HTML/JSON, hálózat nélkül. A látható érték a snapshot recepttartalmát jelenti, nem új élő böngészőmérést.\n\n',
  );
  md.writeln(
    '```json\n${const JsonEncoder.withIndent('  ').convert(summary)}\n```\n',
  );
  for (final e in audit) {
    md.writeln(
      '## ${e['id']} – ${e['location']} – ${e['category']}${e['incidental'] == true ? ' (járulékos)' : ''}\n\nURL: ${e['url']}\n\nSnapshot: ${e['snapshot']}\n\n- Látható: ${jsonEncode(e['visible_page_value'])}\n- JSON-LD: ${jsonEncode(e['json_ld_value'])}\n- Eredeti GT: ${jsonEncode(e['ground_truth_value'])}\n\n${e['evidence']}\n',
    );
  }
  md.writeln(
    '## Korlát és döntés\n\nA 21 eredeti sorból 4 referenciahiba, 17 forráshiba. További 2 teljes elkészítés-referencia hibás (06/08); összesen 6 GT-korrekciós egység. A 10 formázási döntés 5 címutótag + 4 &nbsp; + 1 valódi CR/LF sortörés (a P2 literális escape állítása helyesbítve). Az 5 járulékos megjegyzéshiány miatt a teljes megfigyelt forráshibás sorok száma 22. A 03 tésztanév javítása ezért nem teszi az egész receptet hibamentessé.\n\nA snapshot ellenőrzésében további GT-rövidítések is láthatók (pl. tk/teáskanál, zárójelek); nem mennyiségi konverzióval korrigáltuk őket. A nem érintett, tömör instrukciókat ebben a szűk körben nem írtuk át. A corpus nem tekinthető még minden mezőjében szó szerinti átiratnak.\n\nP3 előtt NEM szükséges extractor-módosítás. Mindmegette: ingredient megjegyzések kiesése és címdekoráció. Nosalty: törtcsonkolás és hibás nullás előtag. Ezeket a parser nem állíthatja helyre találgatással.',
  );
  File('results/p2_5_source_truth_audit.md').writeAsStringSync(md.toString());
  final table = StringBuffer(
    '# Korrigált P2 – batch 01–10\n\nA teljes döntési bizonyíték: p2_5_source_truth_audit.json/md. Az eredeti P2 megmaradt.\n\n| ID | Verdict | Normalizált GT-egyezés | Látható oldal–JSON-LD hibás sor |\n|---|---|---|---|\n',
  );
  for (final r in corrected) {
    table.writeln(
      '| ${r['id']} | ${r['verdict']} | ${r['normalized_match_count']}/${(r['expected_ingredients']! as List).length} | ${r['source_ingredient_mismatches']} |',
    );
  }
  table.writeln(
    '\n```json\n${const JsonEncoder.withIndent('  ').convert(summary)}\n```\n\nA zárójeles megjegyzések miatt a szigorú szövegegyezés nem azonos a tartalmi megfeleléssel. Nincs elveszett teljes hozzávalósor vagy extractor okozta lépésveszteség. A corrected verdict a látható forrástartalom teljességét is figyelembe veszi, nem csupán a régi, tömör referencia egyezését. Tartalmi siker: 3/10 = 30%.',
  );
  File(
    'results/p2_corrected_batch_01-10.md',
  ).writeAsStringSync(table.toString());
  stdout.writeln(jsonEncode(summary));
}
