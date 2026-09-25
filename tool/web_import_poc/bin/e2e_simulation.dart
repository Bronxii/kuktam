// Isolated P4 benchmark support; no production integration or package export.
import 'package:html/parser.dart' as html;
import '../../../lib/recipes/domain/services/recipe_text_parser.dart';

String displayText(String value) => (html.parseFragment(value).text ?? '')
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n')
    .replaceAll('\u00a0', ' ')
    .trim();

String displayTitle(String raw, String url) {
  final host = Uri.parse(url).host.toLowerCase();
  const suffix = ' | Mindmegette.hu';
  // Exact, observed suffix, scoped to the actual site. No title guessing.
  final title = raw.trim();
  return (host == 'mindmegette.hu' || host == 'www.mindmegette.hu') &&
          title.endsWith(suffix)
      ? title.substring(0, title.length - suffix.length)
      : title;
}

List<String> instructionLines(List<Map<String, dynamic>> entries) {
  final lines = <String>[];
  final pending = <String>[];
  void flush() {
    lines.addAll(pending);
    pending.clear();
  }

  for (final entry in entries) {
    final value = displayText(entry['text'] as String);
    switch (entry['kind']) {
      case 'heading':
        pending.add(value);
      case 'section':
        flush();
        lines.add(value);
      case 'step':
        final labels = pending.where((label) => label != value).toList();
        lines.add([...labels, value].join(': '));
        pending.clear();
      default:
        throw FormatException('Unsupported saved instruction kind');
    }
  }
  flush(); // Never drop an orphan heading.
  return lines;
}

Map<String, Object?> simulate(Map<String, dynamic> candidate, String url) {
  final total = Stopwatch()..start();
  final normalizeWatch = Stopwatch()..start();
  final title = displayTitle(candidate['title'] as String, url);
  final rawIngredients = (candidate['ingredients'] as List).cast<String>();
  final preparation = instructionLines(
    (candidate['instructions'] as List).cast<Map<String, dynamic>>(),
  ).join('\n\n');
  final input =
      '$title\n\nHozzávalók:\n${rawIngredients.join('\n')}\n\nElkészítés:\n$preparation';
  normalizeWatch.stop();
  final parserWatch = Stopwatch()..start();
  final parsed = const RecipeTextParser().parse(input);
  parserWatch.stop();
  final buildWatch = Stopwatch()..start();
  final draft = <String, Object?>{
    'title': parsed.title,
    'ingredients': [
      for (final row in parsed.ingredients)
        {
          'sourceOrder': row.sourceOrder,
          'rawText': row.rawText,
          'name': row.name,
          'quantity': row.quantity,
          'canonical_unit': row.unit,
          'warnings': row.warnings.map((w) => w.name).toList(),
        },
    ],
    'preparation': parsed.preparationText,
    'spices': <String>[],
    'unprocessedSegments': parsed.unprocessedSegments,
  };
  buildWatch.stop();
  total.stop();
  return {
    'raw_title': candidate['title'],
    'normalized_title': title,
    'parser_input': input,
    'draft': draft,
    'normalized_preparation': preparation,
    'timing': {
      'normalization_ms': normalizeWatch.elapsedMicroseconds / 1000,
      'parser_ms': parserWatch.elapsedMicroseconds / 1000,
      'draft_build_ms': buildWatch.elapsedMicroseconds / 1000,
      'total_local_ms': total.elapsedMicroseconds / 1000,
    },
  };
}
