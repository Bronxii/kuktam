import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/recipes/domain/services/recipe_import_input_classifier.dart';
import 'package:kuktam/recipes/domain/services/web_import_url_validator.dart';
import 'package:kuktam/recipes/domain/services/web_import_domain_policy.dart';
import 'package:kuktam/recipes/domain/services/recipe_json_ld_extractor.dart';
import 'package:kuktam/recipes/domain/services/web_import_quality_gate.dart';
import 'package:kuktam/recipes/domain/models/web_import_quality.dart';
import 'package:kuktam/recipes/domain/models/web_import_issue.dart';

String script(Object data) =>
    '<script type="application/ld+json">${jsonEncode(data)}</script>';
Map<String, Object?> recipe() => {
  '@type': 'Recipe',
  'name': 'Leves',
  'recipeIngredient': [' 2 dl tej ', '½ tsp salt'],
  'recipeInstructions': 'Keverd.',
};
void main() {
  const classifier = RecipeImportInputClassifier();
  test('URL classifier only routes one complete syntactically valid URL', () {
    for (final s in [
      'https://example.com/a',
      'http://example.com',
      '  https://example.com/a?q=1#x  ',
    ]) {
      expect(classifier.classify(s), RecipeImportInputKind.web);
    }
    for (final s in [
      '',
      'Recept\n1 kg liszt',
      'https://',
      'https://ex ample.com',
      'https://x.com és szöveg',
      'https://x.com https://y.com',
      'ftp://x.com',
      'https://x.com/%xx',
    ]) {
      expect(classifier.classify(s), RecipeImportInputKind.text, reason: s);
    }
  });
  const validator = WebImportUrlValidator();
  test('security rejects literals credentials ports and non-http targets', () {
    for (final s in [
      'http://localhost',
      'https://@example.com',
      'http://127.0.0.1',
      'http://[::1]',
      'http://192.168.1.1',
      'http://169.254.1.1',
      'http://user:pass@example.com',
      'http://example.com:8080',
      'https://example.com:80',
      'file:///a',
      'ftp://example.com',
      'custom://example.com',
      'http://2130706433',
      'http://127.1',
    ]) {
      expect(
        () => validator.validate(s),
        throwsA(isA<WebImportFailure>()),
        reason: s,
      );
    }
    expect(
      validator.validate('https://random.example/path').host,
      'random.example',
    );
    expect(validator.validate('http://random.example:80/path').scheme, 'http');
    expect(
      () => validator.validate(
        'http://random.example',
        previous: Uri.parse('https://random.example'),
      ),
      throwsA(isA<WebImportFailure>()),
    );
  });
  test(
    'DNS addresses reject private/mapped/local/documentation and mixed answers',
    () {
      for (final s in [
        '127.0.0.1',
        '10.0.0.1',
        '172.16.0.1',
        '192.168.1.1',
        '169.254.1.1',
        '100.64.0.1',
        '0.0.0.0',
        '224.0.0.1',
        '192.0.2.1',
        '198.18.0.1',
        '203.0.113.1',
        '::1',
        '::ffff:127.0.0.1',
        'fc00::1',
        'fe80::1',
        '2001:db8::1',
        '2002:7f00:1::',
      ]) {
        expect(validator.isPublic(InternetAddress(s)), false, reason: s);
      }
      expect(validator.isPublic(InternetAddress('8.8.8.8')), true);
      expect(validator.isPublic(InternetAddress('2606:4700:4700::1111')), true);
      expect(
        () => validator.validateAddresses([
          InternetAddress('8.8.8.8'),
          InternetAddress('10.0.0.1'),
        ]),
        throwsA(isA<WebImportFailure>()),
      );
    },
  );
  test('known metadata is not an allowlist, exact hostname only', () {
    const policy = WebImportDomainPolicy();
    expect(
      policy.identify(Uri.parse('https://www.mindmegette.hu')).titleSuffix,
      ' | Mindmegette.hu',
    );
    expect(
      policy.identify(Uri.parse('https://nosalty.hu')).requiresQuantityReview,
      true,
    );
    expect(
      policy
          .identify(validator.validate('https://random.example'))
          .unknownDomain,
      true,
    );
    expect(
      policy
          .identify(Uri.parse('https://nosalty.hu.evil.example'))
          .unknownDomain,
      true,
    );
  });
  test(
    'production extractor preserves arrays graph types instructions and immutable raw rows',
    () {
      final r = recipe();
      r['@type'] = ['Thing', 'Recipe'];
      r['recipeInstructions'] = [
        {
          '@type': 'HowToSection',
          'name': 'Első',
          'itemListElement': [
            {'@type': 'HowToStep', 'name': 'Keverés', 'text': 'Keverd.'},
            'Süsd.',
          ],
        },
      ];
      final out = extractRecipes(
        script({'@type': 'WebPage'}) +
            script([
              {
                '@graph': [r],
              },
            ]),
      );
      expect(out.status, Status.success);
      expect(out.blockCount, 2);
      expect(out.recipeCandidates.single.ingredients, [
        ' 2 dl tej ',
        '½ tsp salt',
      ]);
      expect(
        (out.candidates.single['instructions'] as List).map(
          (e) => (e as Map)['text'],
        ),
        ['Első', 'Keverés', 'Keverd.', 'Süsd.'],
      );
      expect(
        () => out.candidates.single['title'] = 'Changed',
        throwsUnsupportedError,
      );
      expect(
        () => (out.candidates.single['ingredients'] as List).add('x'),
        throwsUnsupportedError,
      );
      expect(
        extractRecipes(script([recipe(), recipe()])).status,
        Status.multipleRecipes,
      );
      expect(
        extractRecipes(
          '<script type="application/ld+json">{bad</script>',
        ).status,
        Status.invalidJsonLd,
      );
      expect(
        extractRecipes(script({'@type': 'WebPage'})).status,
        Status.noRecipe,
      );
      expect(extractRecipes('<p>nothing</p>').status, Status.noJsonLd);
    },
  );
  test(
    'structural gate pass/review/fail and no arbitrary review-ratio rejection',
    () {
      const gate = WebImportQualityGate();
      const policy = WebImportDomainPolicy();
      final known = policy.identify(Uri.parse('https://mindmegette.hu'));
      WebImportQuality evaluate(Map<String, Object?> r) => gate
          .evaluate(extraction: extractRecipes(script(r)), source: known)
          .quality;
      expect(evaluate(recipe()), WebImportQuality.pass);
      for (final field in ['name', 'recipeIngredient', 'recipeInstructions']) {
        final r = recipe();
        r.remove(field);
        expect(evaluate(r), WebImportQuality.fail);
      }
      expect(
        gate
            .evaluate(
              extraction: extractRecipes(script([recipe(), recipe()])),
              source: known,
            )
            .quality,
        WebImportQuality.fail,
      );
      for (final host in ['random.example', 'nosalty.hu']) {
        expect(
          gate
              .evaluate(
                extraction: extractRecipes(script(recipe())),
                source: policy.identify(Uri.parse('https://$host')),
              )
              .quality,
          WebImportQuality.review,
        );
      }
      expect(
        gate
            .evaluate(
              source: known,
              failure: const WebImportFailure(WebImportIssueCode.accessBlocked),
            )
            .allowsHandoff,
        false,
      );
      final review = gate.evaluate(
        source: known,
        extraction: extractRecipes(script(recipe())),
        diagnostics: List.generate(
          100,
          (_) => const WebImportIssue(
            WebImportIssueCode.sourceStructureWarning,
            WebImportSeverity.review,
          ),
        ),
      );
      expect(review.quality, WebImportQuality.review);
      expect(
        gate
            .evaluate(
              source: known,
              extraction: extractRecipes(script(recipe())),
              diagnostics: [
                const WebImportIssue(
                  WebImportIssueCode.invalidQuantity,
                  WebImportSeverity.blocking,
                ),
              ],
            )
            .quality,
        WebImportQuality.fail,
      );
    },
  );
}
