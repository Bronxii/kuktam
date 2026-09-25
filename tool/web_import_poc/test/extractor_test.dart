import 'dart:convert';
import 'dart:io';
import 'package:kuktam_web_import_poc/extractor.dart';
import 'package:kuktam_web_import_poc/runner.dart';
import 'package:test/test.dart';

String script(Object? json) =>
    '<script type="application/ld+json">${jsonEncode(json)}</script>';
Map<String, Object?> recipe() => {
  '@type': 'Recipe',
  'name': 'Recept',
  'recipeIngredient': [' 2 dl tej ', '1½ cup flour', 'salt to taste'],
  'recipeInstructions': 'Keverd.\nSüsd.',
};

void main() {
  final fixtures =
      jsonDecode(File('test/fixtures/structures.json').readAsStringSync())
          as List;
  for (final fixture in fixtures.cast<Map<String, dynamic>>()) {
    test(fixture['case'] as String, () {
      final result = extractRecipes(script(fixture['document']));
      expect(result.status, Status.success);
      final candidate = result.candidates.single;
      final entries = candidate['instructions'] as List<Map<String, String>>;
      expect(entries.map((e) => e['text']), fixture['instructions']);
      expect(candidate['warnings'], isEmpty);
    });
  }
  test('raw ingredients and instruction whitespace preserved', () {
    final raw = recipe();
    final candidate = extractRecipes(script(raw)).candidates.single;
    expect(candidate['ingredients'], raw['recipeIngredient']);
    expect(candidate['preparation'], raw['recipeInstructions']);
  });
  test('multiple blocks and candidates are exposed without selecting', () {
    final result = extractRecipes(
      File('test/fixtures/multiple.html').readAsStringSync(),
    );
    expect(result.status, Status.multipleRecipes);
    expect(result.blockCount, 2);
    expect(result.candidates.map((c) => c['title']), ['Első', 'Második']);
  });
  test('one recipe across multiple blocks', () {
    final result = extractRecipes(
      '${script({'@type': 'WebPage'})}${script(recipe())}',
    );
    expect(result.blockCount, 2);
    expect(result.status, Status.success);
  });
  test('no JSON-LD', () {
    expect(extractRecipes('<p>Recipe</p>').status, Status.noJsonLd);
  });
  test('valid JSON-LD without recipe', () {
    expect(
      extractRecipes(script({'@type': 'Article'})).status,
      Status.noRecipe,
    );
  });
  test('broken JSON', () {
    expect(
      extractRecipes(
        '<script type="application/ld+json">{broken</script>',
      ).status,
      Status.invalidJsonLd,
    );
  });
  test(
    'broken block cannot suppress good candidates or masquerade as success',
    () {
      final result = extractRecipes(
        '<script type="application/ld+json">{</script>${script(recipe())}',
      );
      expect(result.status, Status.invalidJsonLd);
      expect(result.candidates, hasLength(1));
      expect(result.warnings, isNotEmpty);
    },
  );
  for (final field in ['name', 'recipeIngredient', 'recipeInstructions']) {
    test('invalid $field preserves diagnostic raw value', () {
      final raw = recipe()..[field] = 42;
      final result = extractRecipes(script(raw));
      expect(result.status, Status.invalidRecipe);
      expect(result.candidates.single['warnings'], isNotEmpty);
    });
  }
  test('unknown instruction among valid steps does not disappear silently', () {
    final instructions = [
      'Első',
      {'@id': '#unresolved'},
      'Utolsó',
    ];
    final result = extractRecipes(
      script(recipe()..['recipeInstructions'] = instructions),
    );
    expect(result.status, Status.invalidRecipe);
    expect(result.candidates.single['raw_instructions'], instructions);
    expect(result.candidates.single['preparation'], 'Első\nUtolsó');
  });
  test('HTML in text is preserved rather than silently stripped', () {
    final raw = recipe()..['recipeInstructions'] = '<p>Keverd &amp; süsd.</p>';
    expect(
      extractRecipes(script(raw)).candidates.single['preparation'],
      raw['recipeInstructions'],
    );
  });
  test('deep traversal produces a warning instead of partial success', () {
    Object node = recipe();
    for (var i = 0; i < 105; i++) {
      node = {'@graph': node};
    }
    expect(extractRecipes(script(node)).status, Status.invalidJsonLd);
  });
  test(
    'runner captures success metadata and monotonic durations offline',
    () async {
      final body = script(recipe());
      final result = await runUrl(
        'https://example.invalid/recipe',
        fetcher: (_) async {
          return FetchResponse(200, body, utf8.encode(body).length);
        },
      );
      expect(result['status'], 'SUCCESS');
      expect(result['http_status'], 200);
      expect(result['html_bytes'], utf8.encode(body).length);
      for (final key in ['fetch_ms', 'extract_ms', 'total_ms']) {
        expect(result[key], greaterThanOrEqualTo(0));
      }
      expect(
        result['total_ms'],
        greaterThanOrEqualTo(
          (result['fetch_ms'] as double) + (result['extract_ms'] as double),
        ),
      );
    },
  );
  test('HTTP failure is separate from missing JSON-LD', () async {
    final result = await runUrl(
      'https://example.invalid',
      fetcher: (_) async => FetchResponse(403, '', 0),
    );
    expect(result['status'], 'HTTP_ERROR');
    expect(result['http_status'], 403);
    expect(result['extract_ms'], 0);
  });
  test('fetch failure does not stop subsequent URLs', () async {
    final failed = await runUrl(
      'https://example.invalid',
      fetcher: (_) async => throw const SocketException('offline'),
    );
    final next = await runUrl(
      'https://example.invalid',
      fetcher: (_) async => FetchResponse(200, script(recipe()), 100),
    );
    expect(failed['status'], 'FETCH_ERROR');
    expect(next['status'], 'SUCCESS');
  });
  test('non-web URL rejected before network access', () async {
    expect((await runUrl('file:///not-a-web-page'))['status'], 'FETCH_ERROR');
  });
}
