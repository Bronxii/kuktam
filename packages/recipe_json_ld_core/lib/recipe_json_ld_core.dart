import 'dart:convert';
import 'web_recipe_candidate.dart';
import 'package:html/parser.dart' as html;

enum Status {
  fetchError,
  httpError,
  noJsonLd,
  noRecipe,
  invalidJsonLd,
  multipleRecipes,
  invalidRecipe,
  success;

  String get code => switch (this) {
    fetchError => 'FETCH_ERROR',
    httpError => 'HTTP_ERROR',
    noJsonLd => 'NO_JSON_LD',
    noRecipe => 'NO_RECIPE',
    invalidJsonLd => 'INVALID_JSON_LD',
    multipleRecipes => 'MULTIPLE_RECIPES',
    invalidRecipe => 'INVALID_RECIPE',
    success => 'SUCCESS',
  };
}

class Extraction {
  Extraction(
    this.status,
    this.blockCount,
    List<Map<String, Object?>> candidates,
    List<String> warnings,
  ) : candidates = List.unmodifiable(
        candidates.map((c) => WebRecipeCandidate(c).data),
      ),
      warnings = List.unmodifiable(warnings);
  List<WebRecipeCandidate> get recipeCandidates =>
      List.unmodifiable(candidates.map(WebRecipeCandidate.new));
  final Status status;
  final int blockCount;
  final List<Map<String, Object?>> candidates;
  final List<String> warnings;
  Map<String, Object?> toJson() => {
    'status': status.code,
    'json_ld_blocks': blockCount,
    'recipe_candidates': candidates.length,
    'candidates': candidates,
    'warnings': warnings,
  };
}

bool _hasType(Object? value, String type) {
  if (value is List) return value.any((v) => _hasType(v, type));
  return value == type ||
      value == 'https://schema.org/$type' ||
      value == 'http://schema.org/$type';
}

/// No quantity parsing, deduplication, remote context resolution or HTML fallback.
Extraction extractRecipes(String source) {
  final scripts = html
      .parse(source)
      .querySelectorAll('script')
      .where(
        (element) =>
            element.attributes['type']
                ?.trim()
                .toLowerCase()
                .split(';')
                .first
                .trim() ==
            'application/ld+json',
      )
      .toList();
  final warnings = <String>[];
  final candidates = <Map<String, Object?>>[];
  var invalidJson = false;
  void visit(Object? node, int block, String path, int depth) {
    if (depth > 100) {
      invalidJson = true;
      warnings.add('Block $block $path: traversal depth limit reached.');
      return;
    }
    if (node is Map<String, dynamic>) {
      if (_hasType(node['@type'], 'Recipe')) {
        candidates.add(_recipe(node, block, path));
      }
      for (final entry in node.entries) {
        if (entry.value is Map || entry.value is List) {
          visit(entry.value, block, '$path.${entry.key}', depth + 1);
        }
      }
    } else if (node is List) {
      for (var i = 0; i < node.length; i++) {
        visit(node[i], block, '$path[$i]', depth + 1);
      }
    }
  }

  for (var i = 0; i < scripts.length; i++) {
    try {
      final decoded = jsonDecode(scripts[i].text);
      if (decoded is! Map && decoded is! List) {
        throw const FormatException('JSON-LD root must be an object or array');
      }
      visit(decoded, i + 1, r'$', 0);
    } on FormatException {
      invalidJson = true;
      warnings.add('Block ${i + 1}: invalid JSON-LD.');
    }
  }
  final status = scripts.isEmpty
      ? Status.noJsonLd
      : candidates.length > 1
      ? Status.multipleRecipes
      : invalidJson
      ? Status.invalidJsonLd
      : candidates.isEmpty
      ? Status.noRecipe
      : candidates.single['valid'] != true
      ? Status.invalidRecipe
      : Status.success;
  return Extraction(status, scripts.length, candidates, warnings);
}

Map<String, Object?> _recipe(Map<String, dynamic> raw, int block, String path) {
  final warnings = <String>[];
  final ingredients = <String>[];
  final instructions = <Map<String, String>>[];
  final name = raw['name'];
  if (name is! String || name.trim().isEmpty) {
    warnings.add('Missing/invalid name.');
  }
  final rawIngredients = raw['recipeIngredient'];
  if (rawIngredients is List) {
    for (var i = 0; i < rawIngredients.length; i++) {
      final line = rawIngredients[i];
      if (line is String && line.trim().isNotEmpty) {
        ingredients.add(
          line,
        ); // Preserve whitespace, fractions and units exactly.
      } else {
        warnings.add('Invalid ingredient at index $i; see raw_ingredients.');
      }
    }
  } else if (rawIngredients is String && rawIngredients.trim().isNotEmpty) {
    ingredients.add(rawIngredients);
  } else {
    warnings.add('Missing/invalid recipeIngredient.');
  }
  if (ingredients.isEmpty) warnings.add('No nonempty ingredients.');

  void instruction(Object? node, String location, int depth) {
    if (depth > 100) {
      warnings.add('$location: depth limit; see raw_instructions.');
      return;
    }
    if (node is String && node.trim().isNotEmpty) {
      instructions.add({'kind': 'step', 'text': node});
    } else if (node is List) {
      for (var i = 0; i < node.length; i++) {
        instruction(node[i], '$location[$i]', depth + 1);
      }
    } else if (node is Map<String, dynamic> &&
        (_hasType(node['@type'], 'HowToStep') ||
            _hasType(node['@type'], 'HowToSection'))) {
      final section = _hasType(node['@type'], 'HowToSection');
      final label = node['name'];
      final text = node['text'];
      if (label is String && label.trim().isNotEmpty && label != text) {
        instructions.add({
          'kind': section ? 'section' : 'heading',
          'text': label,
        });
      }
      if (text != null) instruction(text, '$location.text', depth + 1);
      if (node.containsKey('itemListElement')) {
        instruction(
          node['itemListElement'],
          '$location.itemListElement',
          depth + 1,
        );
      }
      if (text == null && !node.containsKey('itemListElement')) {
        if (section || label is! String || label.trim().isEmpty) {
          warnings.add(
            '$location: instruction body missing; see raw_instructions.',
          );
        }
      }
      for (final field in ['name', 'description']) {
        if (node[field] != null &&
            (field == 'description' || node[field] is! String)) {
          warnings.add(
            '$location.$field: unsupported content; see raw_instructions.',
          );
        }
      }
    } else {
      warnings.add(
        '$location: unsupported/empty instruction; see raw_instructions.',
      );
    }
  }

  instruction(raw['recipeInstructions'], 'recipeInstructions', 0);
  if (instructions.isEmpty) warnings.add('No instruction text.');
  return {
    'block': block,
    'path': path,
    'valid': warnings.isEmpty,
    'title': name is String ? name : null,
    'ingredients': ingredients,
    'ingredient_count': ingredients.length,
    'instructions': instructions,
    'instruction_count': instructions.length,
    'preparation': instructions.map((s) => s['text']).join('\n'),
    'raw_name': name,
    'raw_ingredients': rawIngredients,
    'raw_instructions': raw['recipeInstructions'],
    'warnings': warnings,
  };
}
