// Offline benchmark only. Imports the unchanged, pure production parser.
import 'dart:convert';
import 'dart:io';
import '../../../lib/recipes/domain/services/recipe_text_parser.dart';
import 'benchmark_p2.dart' show normalize;

// Independently reviewed expected draft values for the actual JSON-LD INPUT,
// not for corrected source quantities. null unit = unsupported semantic unit.
typedef Expected = ({
  String name,
  double? quantity,
  String? unit,
  String? unsupported,
});
Expected e(String name, double? q, String? unit, [String? unsupported]) =>
    (name: name, quantity: q, unit: unit, unsupported: unsupported);
final expected = <List<Expected>>[
  [
    e('Burgonya', 1, 'kg'),
    e('Tojás', 6, 'db'),
    e('Só', 1, 'db'),
    e('Kolbász', 100, 'g'),
    e('Tejföl', 500, 'ml'),
    e('Tojássárgája', 2, 'db'),
    e('Vaj', 2, 'tk'),
    e('Bacon', 100, 'g'),
  ],
  [
    e('sertéshús', 500, 'g'),
    e('zsemle', 2, 'db'),
    e('Vöröshagyma', 1, null, 'fej'),
    e('Olaj', 1, 'db'),
    e('Fokhagyma', 3, null, 'gerezd'),
    e('Tojás', 2, 'db'),
    e('Majoránna', 1, null, 'kis kanál'),
    e('fűszerpaprika', 1, 'tk'),
    e('Só', 1, 'db'),
    e('Bors', 1, 'db'),
    e('Zsemlemorzsa', 100, 'g'),
    e('Olaj', 500, 'ml'),
  ],
  [
    e('színhús', 1, 'kg'),
    e('csont', 500, 'g'),
    e('vegyes zöldség', 500, 'g'),
    e('Hagyma', 1, null, 'fej'),
    e('Fokhagyma', 2, null, 'gerezd'),
    e('Bors', 10, null, 'szem'),
    e('cseresznyepaprika', 1, 'db'),
    e('szeklice', 1, null, 'csapott mokkáskanál'),
    e('Petrezselyem', 1, null, 'csokor'),
    e('Kelkáposzta', 150, 'g'),
    e('Zöldpaprika', 1, 'db'),
    e('Paradicsom', 1, 'db'),
    e('Só', 1, 'db'),
    e('levelestészta', 100, 'g'),
  ],
  [
    e('Tojás', 4, 'db'),
    e('Porcukor', 200, 'g'),
    e('Rum', 100, 'ml'),
    e('Mascarpone', 500, 'g'),
    e('kávé', 300, 'ml'),
    e('Babapiskóta', 1, 'doboz'),
    e('Kakaópor', 1, 'db'),
  ],
  [
    e('Darált dió', 250, 'g'),
    e('Porcukor', 200, 'g'),
    e('Citrom', 1, 'db'),
    e('Vaníliás cukor', 1, 'csomag'),
    e('Baracklekvár', 400, 'g'),
    e('Rum', 2, 'ek'),
    e('Élesztő', 10, 'g'),
    e('Tej', 50, 'ml'),
    e('Liszt', 500, 'g'),
    e('Margarin', 250, 'g'),
    e('Szódabikarbóna', 1, null, 'mokkáskanál'),
    e('Porcukor', 100, 'g'),
    e('Tojássárgája', 1, 'db'),
    e('Vaníliás cukor', 1, 'csomag'),
    e('Tejföl', 2, 'ek'),
    e('Étcsokoládé', 150, 'g'),
    e('Étolaj', 1, 'tk'),
  ],
  [
    e('Csirke alsócomb', 6, 'db'),
    e('Sertészsír', null, 'ek'),
    e('közepes Vöröshagyma', null, 'db'),
    e('Fűszerpaprika', null, 'tk'),
    e('közepes Zöldpaprika', 1, 'db'),
    e('közepes Paradicsom', 1, 'db'),
    e('Tejföl', 200, 'g'),
    e('Finomliszt', 1, 'ek'),
    e('ízlés szerint Só', null, 'db'),
    e('ízlés szerint Bors', null, 'db'),
  ],
  [
    e('Tojás', 3, 'db'),
    e('Cukor', 2, 'ek'),
    e('Vaníliás cukor', 1, 'csomag'),
    e('Finomliszt', 240, 'g'),
    e('Tej', 400, 'ml'),
    e('Szódavíz', 300, 'ml'),
    e('Napraforgó olaj', null, 'ml'),
  ],
  [
    e('Csuszatészta', 400, 'g'),
    e('ízlés szerint Só', null, 'db'),
    e('Füstölt szalonna', 350, 'g'),
    e('Víz', 200, 'ml'),
    e('Tejföl', 200, 'ml'),
    e('Tehéntúró', 450, 'g'),
  ],
  [
    e('Sertéshús az eredeti recept bélszínt ír', 1, 'kg'),
    e('Füstölt szalonna ízlés szerint', 150, 'g'),
    e('Burgonya', 1, 'kg'),
    e('Vöröshagyma', 2, 'db'),
    e('Fokhagyma', 8, null, 'gerezd'),
    e('ízlés szerint Só', null, 'db'),
    e('ízlés szerint Bors', null, 'db'),
    e('ízlés szerint Majoranna', null, 'db'),
    e('ízlés szerint Kakukkfű', null, 'db'),
  ],
  [
    e('Vaj', 200, 'g'),
    e('Finomliszt', 400, 'g'),
    e('Tojás', 2, 'db'),
    e('Tejföl', 200, 'ml'),
    e('Friss élesztő', 20, 'g'),
    e('Tej langyos', 100, 'ml'),
    e('Cukor', 1, null, 'csipet'),
    e('Só', 1, null, 'kávéskanál'),
    e('Sajt', 150, 'g'),
    e('Tojás a kenéshez', 1, 'db'),
  ],
];

void main() {
  final p1 =
      jsonDecode(File('results/p1_batch_01-10.json').readAsStringSync())
          as Map<String, dynamic>;
  final audit =
      jsonDecode(
            File('results/p2_5_source_truth_audit.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  final corrected =
      jsonDecode(
            File('results/p2_corrected_batch_01-10.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  final rows = <Map<String, Object?>>[];
  final recipes = <Map<String, Object?>>[];
  const parser = RecipeTextParser();
  var perRowMicros = 0;
  var batchMicros = 0;
  for (var i = 0; i < 10; i++) {
    final id = (i + 1).toString().padLeft(2, '0');
    final result = (p1['results'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((r) => r['id'] == id);
    final c = (result['candidates'] as List).single as Map<String, dynamic>;
    final inputs = (c['ingredients'] as List).cast<String>();
    if (inputs.length != expected[i].length) {
      throw StateError('Reference count changed $id');
    }
    final recipeWatch = Stopwatch()..start();
    final whole = parser.parse('Hozzávalók:\n${inputs.join('\n')}');
    recipeWatch.stop();
    batchMicros += recipeWatch.elapsedMicroseconds;
    final recipeRows = <Map<String, Object?>>[];
    for (var j = 0; j < inputs.length; j++) {
      final watch = Stopwatch()..start();
      final draft = parser.parse('Hozzávalók:\n${inputs[j]}');
      watch.stop();
      perRowMicros += watch.elapsedMicroseconds;
      final p = draft.ingredients.length == 1 ? draft.ingredients.single : null;
      final oracle = expected[i][j];
      final evidence = (audit['decisions'] as List)
          .cast<Map<String, dynamic>>()
          .where(
            (a) =>
                a['id'] == id &&
                a['location'] == 'ingredient ${j + 1}' &&
                a['category'] == 'SOURCE_JSONLD_ERROR',
          )
          .toList();
      final sourceError = evidence.isNotEmpty;
      final q = p != null && p.quantity == oracle.quantity;
      final u = oracle.unit == null ? null : p != null && p.unit == oracle.unit;
      final n = p != null && normalize(p.name) == normalize(oracle.name);
      final unsupported = oracle.unsupported != null;
      final good = q && u == true && n;
      final converted = RegExp(r'\b(dkg|dl)\b').hasMatch(inputs[j]);
      final parserVerdict = unsupported
          ? 'UNSUPPORTED_UNIT'
          : good
          ? (converted ? 'SUPPORTED_NORMALIZATION' : 'FORMAT_ONLY')
          : 'PARSER_ERROR';
      final row = <String, Object?>{
        'id': id,
        'row': j + 1,
        'raw_extracted_text': inputs[j],
        'source_truth_status': sourceError ? 'SOURCE_ERROR' : 'VALID_SOURCE',
        'source_evidence': evidence,
        'parsed_name': p?.name,
        'parsed_quantity': p?.quantity,
        'parsed_canonical_unit': p?.unit,
        'warnings': p?.warnings.map((w) => w.name).toList() ?? [],
        'unprocessed': draft.unprocessedSegments,
        'output_count': draft.ingredients.length,
        'expected_input_interpretation': {
          'name': oracle.name,
          'quantity': oracle.quantity,
          'unit': oracle.unit,
          'unsupported_unit': oracle.unsupported,
        },
        'quantity_correct_against_input': q,
        'unit_correct_against_input': u,
        'name_correct_against_input': n,
        'parser_verdict': parserVerdict,
        'primary_classification': sourceError ? 'SOURCE_ERROR' : parserVerdict,
        'included_in_parser_accuracy': !sourceError,
        'parse_microseconds': watch.elapsedMicroseconds,
      };
      rows.add(row);
      recipeRows.add(row);
    }
    final valid = recipeRows
        .where((r) => r['included_in_parser_accuracy'] == true)
        .toList();
    int count(String value) =>
        valid.where((r) => r['parser_verdict'] == value).length;
    final correct = count('SUPPORTED_NORMALIZATION') + count('FORMAT_ONLY');
    final correctedRecipe = (corrected['results'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((r) => r['id'] == id);
    if (recipeRows.length - valid.length !=
        correctedRecipe['source_ingredient_mismatches']) {
      throw StateError('Source denominator mismatch');
    }
    // Validate section-level context does not silently lose/reorder/change rows.
    final same =
        whole.ingredients.length == recipeRows.length &&
        List.generate(recipeRows.length, (j) {
          final p = whole.ingredients[j];
          final r = recipeRows[j];
          return p.rawText == r['raw_extracted_text'] &&
              p.name == r['parsed_name'] &&
              p.quantity == r['parsed_quantity'] &&
              p.unit == r['parsed_canonical_unit'] &&
              jsonEncode(p.warnings.map((w) => w.name).toList()) ==
                  jsonEncode(r['warnings']);
        }).every((v) => v);
    recipes.add({
      'id': id,
      'url': result['url'],
      'ingredient_count': inputs.length,
      'source_errors': inputs.length - valid.length,
      'parser_tested_rows': valid.length,
      'parser_correct': correct,
      'parser_incorrect': count('PARSER_ERROR'),
      'unsupported_valid_source_rows': count('UNSUPPORTED_UNIT'),
      'unsupported_all_rows': recipeRows
          .where((r) => r['parser_verdict'] == 'UNSUPPORTED_UNIT')
          .length,
      'warning_rows': recipeRows
          .where((r) => (r['warnings']! as List).isNotEmpty)
          .length,
      'parser_success_percent': 100 * correct / valid.length,
      'parse_microseconds': recipeWatch.elapsedMicroseconds,
      'whole_recipe_vs_single_row_equal': same,
    });
    if (!same) {
      throw StateError(
        '$id row/recipe context discrepancy; inspect before reporting',
      );
    }
  }
  final valid = rows
      .where((r) => r['included_in_parser_accuracy'] == true)
      .toList();
  final supported = valid
      .where((r) => r['parser_verdict'] != 'UNSUPPORTED_UNIT')
      .toList();
  final correct = valid
      .where(
        (r) =>
            r['parser_verdict'] == 'SUPPORTED_NORMALIZATION' ||
            r['parser_verdict'] == 'FORMAT_ONLY',
      )
      .length;
  final unsupported = <String, int>{};
  for (final r in rows.where(
    (r) => r['parser_verdict'] == 'UNSUPPORTED_UNIT',
  )) {
    final unit =
        (r['expected_input_interpretation']!
                as Map<String, Object?>)['unsupported_unit']!
            as String;
    unsupported.update(unit, (n) => n + 1, ifAbsent: () => 1);
  }
  final missingQuantityValid = valid
      .where((r) => (r['warnings']! as List).contains('missingQuantity'))
      .length;
  final sourceRows = rows
      .where((r) => r['source_truth_status'] == 'SOURCE_ERROR')
      .toList();
  final summary = {
    'total_rows': rows.length,
    'source_error_rows': rows.length - valid.length,
    'valid_source_rows': valid.length,
    'correctly_parsed_rows': correct,
    'parser_error_rows': valid
        .where((r) => r['parser_verdict'] == 'PARSER_ERROR')
        .length,
    'unsupported_rows_all': unsupported.values.fold(0, (a, b) => a + b),
    'unsupported_valid_source_rows': valid.length - supported.length,
    'unsupported_units': unsupported,
    'parser_success_valid_source_percent': 100 * correct / valid.length,
    'supported_input_parser_success_percent': 100 * correct / supported.length,
    'source_error_behavior': {
      'invalid_quantity_and_null': sourceRows
          .where(
            (r) =>
                r['parsed_quantity'] == null &&
                (r['warnings']! as List).contains('invalidQuantity'),
          )
          .length,
      'missing_quantity_fallback': sourceRows
          .where((r) => (r['warnings']! as List).contains('missingQuantity'))
          .length,
      'without_warning': sourceRows
          .where((r) => (r['warnings']! as List).isEmpty)
          .length,
    },
    'valid_input_missing_quantity_fallback_rows': missingQuantityValid,
    'explicit_quantity_accuracy': {
      'correct': valid
          .where(
            (r) =>
                !(r['warnings']! as List).contains('missingQuantity') &&
                r['quantity_correct_against_input'] == true,
          )
          .length,
      'denominator': valid.length - missingQuantityValid,
    },
    'quantity': {
      'correct': valid
          .where((r) => r['quantity_correct_against_input'] == true)
          .length,
      'denominator': valid.length,
      'note':
          'Missing quantity uses accepted 1 db fallback; not a claim that the source stated 1.',
    },
    'unit': {
      'correct': supported
          .where((r) => r['unit_correct_against_input'] == true)
          .length,
      'denominator': supported.length,
      'not_applicable_unsupported': valid.length - supported.length,
    },
    'name': {
      'correct': valid
          .where((r) => r['name_correct_against_input'] == true)
          .length,
      'denominator': valid.length,
      'note':
          'Unit phrases separated from name; meaningful descriptors/notes retained. Unsupported units included; compare case/whitespace insensitive.',
    },
    'timing': {
      'recipe_calls_total_us': batchMicros,
      'recipe_calls_average_us': batchMicros / 10,
      'row_calls_total_us': perRowMicros,
      'row_calls_average_us': perRowMicros / 100,
      'all_parser_calls_total_us': batchMicros + perRowMicros,
      'note':
          'Single pass, desktop Dart JIT Stopwatch; first recipe includes cold/JIT cost; row calls run after its recipe call. Not phone/release performance; no IO inside timed regions.',
    },
    'coverage_note':
        'Natural dataset only: positive decimal dot 0.5 dl; no comma quantities, slash/Unicode fractions, kk, explicit l/ml/g→kg threshold or foreign units. Existing production tests cover additional cases but are NOT corpus benchmark evidence.',
  };
  final report = {
    'method':
        'Offline unchanged RecipeTextParser. Each row and each recipe passed with Hozzávalók heading; no title/preparation, no P4 draft assembly. Explicit independent expected values, no normalizer reused as oracle. 22 source errors excluded from ALL accuracy denominators. Unsupported units separated from parser errors and shown both all-source/valid-source.',
    'summary': summary,
    'recipes': recipes,
    'rows': rows,
  };
  File('results/p3_parser_batch_01-10.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  final md = StringBuffer(
    '# P3 – RecipeTextParser kompatibilitás, batch 01–10\n\nCsak mentett input, változatlan production parser. Minden sor és minden teljes hozzávalólista `Hozzávalók:` fejléccel futott; ez a parser publikus szöveg API-jának kontextusa, nem P4-import. Nincs hálózat.\n\n',
  );
  md.writeln(
    '```json\n${const JsonEncoder.withIndent('  ').convert(summary)}\n```\n',
  );
  md.writeln(
    '| ID | Sor | Forráshiba | Értékelt | Helyes | Parserhiba | Unsupported (értékelt) | Siker % | Idő µs |\n|---|---|---|---|---|---|---|---|---|',
  );
  for (final r in recipes) {
    md.writeln(
      '| ${r['id']} | ${r['ingredient_count']} | ${r['source_errors']} | ${r['parser_tested_rows']} | ${r['parser_correct']} | ${r['parser_incorrect']} | ${r['unsupported_valid_source_rows']} | ${(r['parser_success_percent']! as double).toStringAsFixed(2)} | ${r['parse_microseconds']} |',
    );
  }
  md.writeln('\n## Soronkénti bizonyíték\n');
  for (final r in rows) {
    md.writeln(
      '- **${r['id']}/${r['row']}** `${r['raw_extracted_text']}` → `${r['parsed_name']}` | ${r['parsed_quantity']} | ${r['parsed_canonical_unit']}; warning: ${r['warnings']}; source: ${r['source_truth_status']}; parser: ${r['parser_verdict']}; ${r['parse_microseconds']} µs.',
    );
  }
  md.writeln(
    '\n## Értelmezés\n\nA nem támogatott mennyiségi szavak többsége a névben marad db fallback mellett, warning nélkül; csipet esetén explicit unknownUnit és db fallback van. Ezeket nem keverjük a támogatott input parserhibáival. A fej/gerezd/szem/csokor nem automatikusan felcserélhető db-vel, a különböző kanalakat sem szabad önkényesen tk-vá alakítani.\n\nA `1 közepes db ...` két helyes forrássornál a db szó a névben marad: a parser csak a számot közvetlenül követő unitot keresi. A közepes jelző megőrzendő, a db a unit mezőbe tartozik. Ez a benchmark névszétválasztási hibakritériuma; nem adatvesztés.\n\nA hibás 0 inputok invalidQuantity warningot és null quantityt kapnak; a pozitívra csonkolt forrásmennyiségek hibaüzenet nélkül normalizálódhatnak. A parser nem tudja rekonstruálni a forrásból hiányzó törtet/megjegyzést.\n\nLegkisebb későbbi javítási irány: ismert, nem canonical mennyiségi szavak következetes unknownUnit figyelmeztetése és rawText-megőrzés; külön, tesztelt szabály a jelzővel elválasztott canonical db felismerésére. Többszavas kanálkifejezések és unit-szemantika termékdöntést igényelnek, nem vak aliasbővítést.\n\nP4 felügyelt, szerkeszthető szimulációra alkalmas külön jóváhagyással; megbízható automatikus mentésre nem. Production parser nem módosult.',
  );
  File('results/p3_parser_batch_01-10.md').writeAsStringSync(md.toString());
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(summary));
}
