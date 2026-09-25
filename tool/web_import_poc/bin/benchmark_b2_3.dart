// Offline measurement only; production parser remains unchanged.
import 'dart:convert';
import 'dart:io';
import '../../../lib/recipes/domain/services/recipe_text_parser.dart';

void main() {
  final b1 =
      jsonDecode(File('results/b2_1_batch_11-20.json').readAsStringSync())
          as Map<String, dynamic>;
  const parser = RecipeTextParser();
  final rows = <Map<String, Object?>>[], recipes = <Map<String, Object?>>[];
  for (final r in (b1['results'] as List).cast<Map<String, dynamic>>()) {
    final id = int.parse(r['id'] as String);
    if (id < 11 || id > 20) throw StateError('Scope violation');
    final c = (r['candidates'] as List).single as Map<String, dynamic>;
    final inputs = (c['ingredients'] as List).cast<String>();
    final clock = Stopwatch()..start();
    final whole = parser.parse('Hozzávalók:\n${inputs.join('\n')}');
    clock.stop();
    final singleRows = <Map<String, Object?>>[];
    for (var i = 0; i < inputs.length; i++) {
      final t = Stopwatch()..start();
      final d = parser.parse('Hozzávalók:\n${inputs[i]}');
      t.stop();
      final p = d.ingredients.length == 1 ? d.ingredients.single : null;
      final row = <String, Object?>{
        'id': '$id',
        'row': i + 1,
        'domain': r['domain'],
        'raw_extracted_text': inputs[i],
        'parsed_name': p?.name,
        'parsed_quantity': p?.quantity,
        'raw_quantity': p?.rawQuantityText,
        'parsed_unit': p?.unit,
        'warnings': p?.warnings.map((w) => w.name).toList() ?? [],
        'unprocessed': d.unprocessedSegments,
        'output_count': d.ingredients.length,
        'parser_us': t.elapsedMicroseconds,
      };
      rows.add(row);
      singleRows.add(row);
    }
    final equal =
        whole.ingredients.length == singleRows.length &&
        List.generate(singleRows.length, (i) {
          final p = whole.ingredients[i], r = singleRows[i];
          return p.name == r['parsed_name'] &&
              p.quantity == r['parsed_quantity'] &&
              p.unit == r['parsed_unit'] &&
              p.rawText == r['raw_extracted_text'] &&
              jsonEncode(p.warnings.map((w) => w.name).toList()) ==
                  jsonEncode(r['warnings']);
        }).every((v) => v);
    recipes.add({
      'id': '$id',
      'url': r['url'],
      'parser_us': clock.elapsedMicroseconds,
      'ingredient_count': inputs.length,
      'whole_vs_single_equal': equal,
    });
  }
  File('results/b2_3_parser_measurements.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'recipes': recipes, 'rows': rows})}\n',
  );
  stdout.writeln(
    'Measured ${rows.length} rows / ${recipes.length} recipes offline.',
  );
}
