import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import '../../../lib/recipes/domain/services/recipe_text_parser.dart';

void main() {
  final report =
      jsonDecode(
            File('results/b3_3_parser_batch_21-28.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  final rows = (report['rows'] as List).cast<Map<String, dynamic>>();
  test(
    'classification partitions 82 valid rows and excludes blocked sources',
    () {
      final s = report['summary'] as Map;
      expect(rows.length, 82);
      expect(
        rows.every(
          (r) =>
              int.parse(r['id'] as String) >= 21 &&
              int.parse(r['id'] as String) <= 28,
        ),
        true,
      );
      expect(s['supported'], 51);
      expect(s['correct_supported'], 51);
      expect(s['parser_errors'], 0);
      expect(s['unsupported_rows'], 31);
      expect(s['unsupported_unit_rows'], 27);
      expect(s['parser_limitation_rows'], 4);
      expect(rows.where((r) => r['silent_fallback'] == true).length, 21);
      expect(
        rows
            .where((r) => r['silent_fallback'] == true)
            .map((r) => r['id'])
            .toSet()
            .length,
        6,
      );
      expect(report['source_group_heading_omissions'], 4);
    },
  );
  test(
    'saved measurements replay exactly through unchanged production parser',
    () {
      const parser = RecipeTextParser();
      for (final r in rows) {
        final draft = parser.parse('Hozzávalók:\n${r['raw_extracted_text']}');
        expect(draft.ingredients.length, 1);
        final p = draft.ingredients.single;
        expect(p.name, r['parsed_name']);
        expect(p.quantity, r['parsed_quantity']);
        expect(p.unit, r['parsed_unit']);
        expect(p.rawQuantityText, r['raw_quantity']);
        expect(p.warnings.map((w) => w.name).toList(), r['warnings']);
      }
    },
  );
  test(
    'semantic cloves, unicode fraction and compound limitations stay separate',
    () {
      Map<String, dynamic> row(String id, int n) =>
          rows.singleWhere((r) => r['id'] == id && r['row'] == n);
      expect(row('23', 5)['verdict'], 'CORRECT');
      expect(row('21', 3)['verdict'], 'UNSUPPORTED_UNIT');
      expect(row('28', 6)['parsed_quantity'], 0.5);
      expect(row('28', 6)['silent_fallback'], true);
      expect(row('26', 6)['verdict'], 'PARSER_LIMITATION');
      expect(row('26', 6)['parsed_quantity'], null);
      expect(row('26', 1)['quantity_correct'], null);
      final source =
          jsonDecode(
                File(
                  'results/b3_2_content_source_quality.json',
                ).readAsStringSync(),
              )
              as Map;
      for (final recipe
          in (source['recipes'] as List).cast<Map<String, dynamic>>()) {
        expect(
          rows
              .where((r) => r['id'] == recipe['id'])
              .map((r) => r['raw_extracted_text'])
              .toList(),
          (recipe['ingredients'] as List)
              .cast<Map<String, dynamic>>()
              .map((r) => r['json_ld_text'])
              .toList(),
        );
      }
    },
  );
}
