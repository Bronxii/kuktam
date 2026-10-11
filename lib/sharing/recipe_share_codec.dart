import 'dart:convert';
import 'dart:typed_data';
import '../core/domain/measurement_units.dart';
import '../export/domain/recipe_export.dart';
import '../export/domain/recipe_export_formatter.dart';
import '../recipes/domain/models/recipe.dart';

class RecipeShareFailure implements Exception {
  const RecipeShareFailure(this.code);
  final String code;
  String get message => switch (code) {
    'format' => 'Nem Kuktám receptfájl.',
    'version' => 'Nem támogatott receptverzió.',
    'size' => 'Túl nagy receptfájl. Legfeljebb 256 KiB fogadható.',
    'read' => 'A recept nem olvasható. Nyisd meg újra a fájlt.',
    'busy' => 'Előbb fejezd be a várakozó receptimportokat.',
    'session' => 'A fiók megváltozott. Nyisd meg újra a receptfájlt.',
    _ => 'Sérült vagy nem támogatott adatokat tartalmazó receptfájl.',
  };
  @override
  String toString() => 'RecipeShareFailure($code)';
}

abstract final class RecipeShareCodec {
  static const mime = 'application/vnd.kuktam.recipe+json';
  static const maxBytes = 256 * 1024;
  static String filename(String name) =>
      '${safeRecipeFileName(name)}.kuktamrecipe';

  static Uint8List encode(Recipe recipe) {
    try {
      final content = ExportRecipe.fromRecipe(recipe).toContentJson();
      _recipe(
        content,
      ); // Same strict policy for outbound legacy data and inbound data.
      final bytes = utf8.encode(
        '${const JsonEncoder.withIndent('  ').convert({'format': 'kuktam.recipe', 'version': 1, 'recipe': content})}\n',
      );
      if (bytes.length > maxBytes) throw const RecipeShareFailure('size');
      return Uint8List.fromList(bytes);
    } on RecipeShareFailure {
      rethrow;
    } catch (_) {
      throw const RecipeShareFailure('invalid');
    }
  }

  static Recipe decode(List<int> bytes) {
    if (bytes.length > maxBytes) throw const RecipeShareFailure('size');
    try {
      final text = utf8.decode(bytes, allowMalformed: false);
      // Bound nesting before jsonDecode; deeply nested untrusted objects cannot exhaust recursion.
      var depth = 0;
      var quoted = false;
      var escaped = false;
      for (final c in text.codeUnits) {
        if (quoted) {
          if (escaped) {
            escaped = false;
          } else if (c == 92) {
            escaped = true;
          } else if (c == 34) {
            quoted = false;
          }
        } else if (c == 34) {
          quoted = true;
        } else if (c == 123 || c == 91) {
          if (++depth > 8) throw const RecipeShareFailure('invalid');
        } else if (c == 125 || c == 93) {
          depth--;
        }
      }
      final root = _object(jsonDecode(text), {'format', 'version', 'recipe'});
      if (root['format'] != 'kuktam.recipe') {
        throw const RecipeShareFailure('format');
      }
      if (root['version'] is! int) throw const RecipeShareFailure('invalid');
      if (root['version'] != 1) throw const RecipeShareFailure('version');
      return _recipe(root['recipe']);
    } on RecipeShareFailure {
      rethrow;
    } catch (_) {
      throw const RecipeShareFailure('invalid');
    }
  }

  static Map<String, dynamic> _object(Object? value, Set<String> fields) {
    if (value is! Map<String, dynamic> ||
        value.length != fields.length ||
        !fields.every(value.containsKey)) {
      throw const RecipeShareFailure('invalid');
    }
    return value;
  }

  static String _string(Object? value, {bool empty = false}) {
    if (value is! String || (!empty && value.trim().isEmpty)) {
      throw const RecipeShareFailure('invalid');
    }
    if (utf8.decode(utf8.encode(value)) != value) {
      throw const RecipeShareFailure('invalid');
    }
    return value;
  }

  static Recipe _recipe(Object? value) {
    final r = _object(value, {'name', 'ingredients', 'spices', 'preparation'});
    if (r['ingredients'] is! List || r['spices'] is! List) {
      throw const RecipeShareFailure('invalid');
    }
    final ingredients = <RecipeIngredient>[];
    for (final item in r['ingredients'] as List) {
      final i = _object(item, {'name', 'quantity', 'unit'});
      final q = i['quantity'];
      final unit = _string(i['unit']);
      if (q is! num ||
          !q.isFinite ||
          q <= 0 ||
          !MeasurementUnits.values.contains(unit)) {
        throw const RecipeShareFailure('invalid');
      }
      ingredients.add(
        RecipeIngredient(
          name: _string(i['name']),
          quantity: q.toDouble(),
          unit: unit,
        ),
      );
    }
    return Recipe(
      name: _string(r['name']),
      ingredients: ingredients,
      spices: [
        for (final s in r['spices'] as List)
          RecipeSpice(name: _string(_object(s, {'name'})['name'])),
      ],
      preparation: _string(r['preparation'], empty: true),
    );
  }
}
