import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/recipes/domain/models/web_import_issue.dart';
import 'package:kuktam/recipes/domain/models/recipe_import_review_metadata.dart';
import 'package:kuktam/recipes/domain/models/web_import_quality.dart';
import 'package:kuktam/recipes/domain/services/recipe_json_ld_extractor.dart';
import 'package:kuktam/recipes/domain/services/recipe_text_parser.dart';
import 'package:kuktam/recipes/domain/services/web_import_domain_policy.dart';
import 'package:kuktam/recipes/domain/services/web_recipe_import_service.dart';
import 'package:kuktam/recipes/domain/services/web_recipe_normalizer.dart';

Extraction candidate(
  List<String> rows, {
  String title = 'Leves',
  Object instructions = 'Főzd meg.',
}) => extractRecipes(
  '<script type="application/ld+json">${jsonEncode({'@type': 'Recipe', 'name': title, 'recipeIngredient': rows, 'recipeInstructions': instructions})}</script>',
);
const service = WebRecipeImportService();
WebRecipeImportResult prepare(
  List<String> rows, {
  String host = 'mindmegette.hu',
}) => service.prepare(
  candidate(rows),
  sourceUrl: Uri.parse('https://$host/recept'),
  importId: 'test',
);

void main() {
  test(
    'normalization is domain-bound, preserves raw data, entities and instruction order',
    () {
      final c = candidate(
        [' 2 dl tej &nbsp; '],
        title: ' Leves &amp; rizs | Mindmegette.hu ',
        instructions: [
          {
            '@type': 'HowToSection',
            'name': 'Előkészítés',
            'itemListElement': [
              {
                '@type': 'HowToStep',
                'name': 'Vágás',
                'text': '<p>Aprítsd&nbsp; fel.</p><p>Tedd félre.</p>',
              },
              {
                '@type': 'HowToStep',
                'name': 'Főzés',
                'text': 'Főzés: Keverd össze.',
              },
            ],
          },
          'Tálald.',
        ],
      ).recipeCandidates.single;
      const n = WebRecipeNormalizer();
      final known = n.normalize(
        c,
        const WebImportSourceMetadata(WebImportSource.mindmegette),
      );
      final unknown = n.normalize(
        c,
        const WebImportSourceMetadata(WebImportSource.generic),
      );
      expect(known.title, 'Leves & rizs');
      expect(unknown.title, 'Leves & rizs | Mindmegette.hu');
      expect(known.rawTitle, c.title);
      expect(known.rawIngredients, [' 2 dl tej &nbsp; ']);
      expect(known.ingredients, ['2 dl tej']);
      expect(
        known.preparation,
        'Előkészítés\n\nVágás: Aprítsd fel.\nTedd félre.\n\nFőzés: Keverd össze.\n\nTálald.',
      );
      expect(
        n
            .normalize(
              candidate([
                '1 db alma',
              ], title: 'Alma | Other.hu').recipeCandidates.single,
              const WebImportSourceMetadata(WebImportSource.mindmegette),
            )
            .title,
        'Alma | Other.hu',
      );
    },
  );

  test(
    'adapter uses unchanged parser conversions and retains parser evidence',
    () {
      for (final row in [
        '20 dkg liszt',
        '2 dl tej',
        '1 kk só',
        '0 g liszt',
        '1 csipet só',
      ]) {
        final direct = const RecipeTextParser()
            .parse('Hozzávalók:\n$row')
            .ingredients
            .single;
        final result = prepare([row]);
        final value = result.review!.rows.single.value;
        expect(value.name, direct.name);
        expect(value.quantity, direct.quantity);
        expect(value.unit, direct.unit);
        expect(value.rawQuantityText, direct.rawQuantityText);
        expect(value.warnings, direct.warnings);
        expect(value.rawText, row);
        expect(value.sourceOrder, 0);
      }
      final r = prepare(['20 dkg liszt', '2 dl tej', '1 kk só']);
      expect(r.draft!.ingredients.map((i) => i.quantity), [200, 200, 1]);
      expect(r.draft!.ingredients.map((i) => i.unit), ['g', 'ml', 'tk']);
      expect(r.quality.quality, WebImportQuality.pass);
    },
  );

  test('proven unit-like tokens get review without adding canonical units', () {
    for (final token in [
      'fej',
      'gerezd',
      'csipet',
      'csokor',
      'mokkáskanál',
      'kávéskanál',
      'kis kanál',
      'tbsp',
      'tsp',
      'cloves',
      'bunch',
      'handful',
      'rashers',
      'stick',
      'sprigs',
      'cans',
      'tin',
      'tins',
      'piece',
    ]) {
      final r = prepare(['2 $token alapanyag']);
      expect(
        r.review!.rows.single.issues.map((i) => i.code),
        contains(WebImportIssueCode.unsupportedUnit),
        reason: token,
      );
      expect(r.quality.quality, WebImportQuality.review, reason: token);
      expect(
        r.review!.rows.single.issues.every(
          (i) => i.rowId == 'test:0' && i.evidence != null,
        ),
        true,
      );
    }
    final silent = prepare(['2 tbsp olaj']).review!.rows.single;
    expect(silent.value.warnings, isEmpty);
    expect(
      silent.issues.map((i) => i.code),
      contains(WebImportIssueCode.silentDbFallbackRisk),
    );
  });

  test(
    'benign Hungarian adjectives and supported fractions do not cause false positive',
    () {
      for (final text in [
        '2 nagy alma',
        '1 közepes hagyma',
        '3 kisebb paradicsom',
        '½ kg liszt',
        '1/2 kg liszt',
        '1,5 kg liszt',
      ]) {
        final r = prepare([text]);
        expect(r.quality.quality, WebImportQuality.pass, reason: text);
        expect(r.review!.rows.single.issues, isEmpty, reason: text);
      }
    },
  );

  test(
    'range multiplier mixed fraction and textual quantity are audited not repaired',
    () {
      for (final text in [
        '2-3 tbsp olaj',
        '2–3 alma',
        '2 x 400 g paradicsom',
        '2x400g paradicsom',
        '1 1/2 kg liszt',
        'half a jar sauce',
        '⅓ cup sugar',
      ]) {
        final r = prepare(['1 db alma', text]);
        expect(
          r.review!.rows.last.issues.map((i) => i.code),
          contains(WebImportIssueCode.unresolvedQuantityExpression),
          reason: text,
        );
        expect(r.review!.rows.last.value.rawText, text);
        expect(r.quality.quality, WebImportQuality.review);
      }
    },
  );

  test(
    'invalid and ambiguous parser warnings persist, missing quantity review and zero usable FAIL',
    () {
      for (final text in ['0 g liszt', '1 2 liszt', 'NaN g liszt']) {
        final r = prepare([text]);
        expect(r.quality.quality, WebImportQuality.fail, reason: text);
        expect(r.editorDraft, isNull);
        final accepted = r.review!.acceptRow('test:0');
        expect(accepted.canSave, false);
        expect(
          service.evaluate(accepted).quality.quality,
          WebImportQuality.fail,
        );
      }
      expect(
        prepare(['só']).review!.rows.single.issues.map((i) => i.code),
        contains(WebImportIssueCode.missingQuantity),
      );
      expect(
        prepare(['1 csipet só']).review!.rows.single.issues.map((i) => i.code),
        contains(WebImportIssueCode.unknownUnit),
      );
      expect(
        prepare(['1 db alma', '0 g liszt']).quality.quality,
        WebImportQuality.review,
      );
      expect(prepare(['1 db alma', '0 g liszt']).review!.canSave, false);
    },
  );

  test('Nosalty and unknown source review do not block handoff', () {
    for (final host in ['nosalty.hu', 'unknown.example']) {
      final r = prepare(['1 kg liszt'], host: host);
      expect(r.quality.quality, WebImportQuality.review);
      expect(r.editorDraft, isNotNull);
      expect(
        r.review!.issues.single.code,
        host == 'nosalty.hu'
            ? WebImportIssueCode.knownSourceRisk
            : WebImportIssueCode.unverifiedSource,
      );
      expect(
        service.evaluate(r.review!.acceptRecipe()).quality.quality,
        WebImportQuality.pass,
      );
    }
  });

  test(
    'review acceptance invalidated on edit, correction re-audited, deletion drops state',
    () {
      final r = prepare([
        '2 gerezd fokhagyma',
        '1 db alma',
      ], host: 'nosalty.hu');
      var review = r.review!.acceptRecipe().acceptRow('test:0');
      expect(review.canSave, true);
      review = service.editRow(
        review,
        'test:0',
        name: 'gerezd fokhagyma',
        quantity: 3,
        unit: 'db',
      );
      expect(review.rows.first.accepted, false);
      expect(
        review.unresolved.map((i) => i.code),
        contains(WebImportIssueCode.knownSourceRisk),
      );
      review = service.editRow(
        review,
        'test:0',
        name: 'fokhagyma',
        quantity: 3,
        unit: 'g',
      );
      expect(review.rows.first.issues, isEmpty);
      expect(review.rows.first.id, 'test:0');
      review = review.removeRow('test:0');
      expect(review.rows.single.id, 'test:1');
      expect(review.unresolved.any((i) => i.rowId == 'test:0'), false);
      expect(
        service.evaluate(review.acceptRecipe()).quality.quality,
        WebImportQuality.pass,
      );
      expect(
        service
            .evaluate(review.withContent(title: '', preparation: 'Főzd.'))
            .quality
            .quality,
        WebImportQuality.fail,
      );
      expect(
        service
            .evaluate(review.withContent(title: 'Leves', preparation: ''))
            .quality
            .quality,
        WebImportQuality.fail,
      );
      expect(
        service.evaluate(review.removeRow('test:1')).quality.quality,
        WebImportQuality.fail,
      );
    },
  );

  test(
    'many review rows stay editable; info does not block; recipe edits revoke approval',
    () {
      final result = prepare(List.generate(40, (_) => '2 tbsp olaj'));
      expect(result.quality.quality, WebImportQuality.review);
      expect(result.editorDraft, isNotNull);
      final accepted = prepare([
        '1 db alma',
      ], host: 'nosalty.hu').review!.acceptRecipe();
      expect(accepted.canSave, true);
      expect(
        accepted
            .withContent(title: 'Másik', preparation: accepted.preparation)
            .canSave,
        false,
      );
      expect(accepted.withContent(title: '', preparation: '').canSave, false);
      expect(accepted.removeRow('test:0').canSave, false);
      final bad = prepare(['1 db alma']);
      final edited = service
          .editRow(bad.review!, 'test:0', name: '', quantity: -1, unit: 'cup')
          .acceptRow('test:0');
      expect(edited.canSave, false);
      expect(service.evaluate(edited).quality.quality, WebImportQuality.fail);
    },
  );

  test(
    'parser warnings are distinct from silent fallback; INFO never requires acceptance',
    () {
      final warned = prepare(['1 csipet só']).review!.rows.single;
      expect(warned.value.warnings, isNotEmpty);
      expect(
        warned.issues.map((i) => i.code),
        isNot(contains(WebImportIssueCode.silentDbFallbackRisk)),
      );
      final plain = prepare(['1 db alma']).review!;
      final info = RecipeImportReviewMetadata(
        title: plain.title,
        preparation: plain.preparation,
        rows: plain.rows,
        issues: [
          const WebImportIssue(
            WebImportIssueCode.sourceStructureWarning,
            WebImportSeverity.info,
            origin: WebImportIssueOrigin.normalization,
          ),
        ],
      );
      expect(info.canSave, true);
      expect(service.evaluate(info).quality.quality, WebImportQuality.pass);
    },
  );

  test(
    'all saved benchmark instruction entries and ingredient rows preserved offline',
    () {
      var entries = 0, steps = 0, rows = 0, recipes = 0;
      for (final file in [
        'p1_batch_01-10.json',
        'b2_1_batch_11-20.json',
        'b3_1_batch_21-30.json',
      ]) {
        final data =
            jsonDecode(
                  File('tool/web_import_poc/results/$file').readAsStringSync(),
                )
                as Map;
        for (final result in data['results'] as List) {
          if (result['status'] != 'SUCCESS') continue;
          final candidates = (result['candidates'] as List)
              .map((c) => Map<String, Object?>.from(c as Map))
              .toList();
          final extraction = Extraction(
            Status.success,
            result['json_ld_blocks'] as int,
            candidates,
            [],
          );
          final output = service.prepare(
            extraction,
            sourceUrl: Uri.parse(result['url'] as String),
            importId: '$file:${result['id']}',
          );
          expect(output.normalized, isNotNull);
          expect(
            output.draft!.ingredients.map((r) => r.rawText),
            candidates.single['ingredients'],
          );
          rows += output.draft!.ingredients.length;
          recipes++;
          final instructions = candidates.single['instructions'] as List;
          expect(
            output.normalized!.instructionEntries.length,
            instructions.length,
          );
          var stepCursor = 0;
          for (var i = 0; i < instructions.length; i++) {
            final text = output.normalized!.instructionEntries[i];
            expect(
              output.draft!.preparationText,
              contains(text),
              reason: '$file ${result['id']} step $i',
            );
            entries++;
            if (instructions[i]['kind'] == 'step') {
              final index = output.draft!.preparationText.indexOf(
                text,
                stepCursor,
              );
              expect(
                index,
                greaterThanOrEqualTo(stepCursor),
                reason: 'Step order $file ${result['id']} $i',
              );
              stepCursor = index + text.length;
              steps++;
            }
          }
        }
      }
      expect(recipes, 28);
      expect(rows, 292);
      expect(entries, 205);
      expect(steps, greaterThan(0));
    },
  );
}
