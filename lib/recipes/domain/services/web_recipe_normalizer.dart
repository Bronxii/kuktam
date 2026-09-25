import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import '../models/web_recipe_candidate.dart';
import 'web_import_domain_policy.dart';

class NormalizedWebRecipe {
  NormalizedWebRecipe({
    required this.rawTitle,
    required this.title,
    required Iterable<String> rawIngredients,
    required Iterable<String> ingredients,
    required Iterable<String> instructionEntries,
    required this.preparation,
  }) : rawIngredients = List.unmodifiable(rawIngredients),
       ingredients = List.unmodifiable(ingredients),
       instructionEntries = List.unmodifiable(instructionEntries);
  final String rawTitle, title, preparation;
  final List<String> rawIngredients, ingredients, instructionEntries;
}

/// Display normalization only. Never interprets or repairs quantities/units.
class WebRecipeNormalizer {
  const WebRecipeNormalizer();
  String text(String value, {bool multiline = false}) {
    final out = StringBuffer();
    void visit(Node node) {
      if (node is Text) {
        out.write(node.data);
        return;
      }
      if (node is Element) {
        if (const ['script', 'style'].contains(node.localName)) return;
        final block = const [
          'p',
          'div',
          'li',
          'br',
          'section',
        ].contains(node.localName);
        if (block) out.write('\n');
        for (final child in node.nodes) {
          visit(child);
        }
        if (block) out.write('\n');
      } else {
        for (final child in node.nodes) {
          visit(child);
        }
      }
    }

    visit(html.parseFragment(value));
    final lines = out
        .toString()
        .replaceAll('\r', '\n')
        .split('\n')
        .map((s) => s.replaceAll(RegExp(r'[\s\u00a0]+'), ' ').trim())
        .where((s) => s.isNotEmpty);
    return lines.join(multiline ? '\n' : ' ');
  }

  NormalizedWebRecipe normalize(
    WebRecipeCandidate candidate,
    WebImportSourceMetadata source,
  ) {
    final rawTitle = candidate.title ?? '';
    var title = text(rawTitle);
    final suffix = source.titleSuffix;
    if (suffix != null && title.endsWith(suffix)) {
      title = title.substring(0, title.length - suffix.length).trim();
    }
    final entries = (candidate.data['instructions'] as List).cast<Map>();
    final normalized = [
      for (final e in entries) text(e['text'] as String, multiline: true),
    ];
    final blocks = <String>[];
    for (var i = 0; i < entries.length; i++) {
      final current = normalized[i];
      if (entries[i]['kind'] == 'heading' &&
          i + 1 < entries.length &&
          entries[i + 1]['kind'] == 'step') {
        final body = normalized[++i];
        final label = current.replaceFirst(RegExp(r':$'), '');
        blocks.add(
          body == current || body == label || body.startsWith('$label:')
              ? body
              : '$label: $body',
        );
      } else if (current.isNotEmpty) {
        blocks.add(current);
      }
    }
    return NormalizedWebRecipe(
      rawTitle: rawTitle,
      title: title,
      rawIngredients: candidate.ingredients,
      ingredients: candidate.ingredients.map((s) => text(s)),
      instructionEntries: normalized,
      preparation: blocks.join('\n\n'),
    );
  }
}
