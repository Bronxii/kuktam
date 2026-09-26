import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/recipes/data/repositories/recipe_repository.dart';
import 'package:kuktam/recipes/domain/models/recipe.dart';
import 'package:kuktam/recipes/domain/models/recipe_import_review_metadata.dart';
import 'package:kuktam/recipes/domain/models/web_import_issue.dart';
import 'package:kuktam/recipes/domain/models/web_recipe_import_handoff.dart';
import 'package:kuktam/recipes/presentation/screens/add_recipe_screen.dart';
import 'package:kuktam/recipes/presentation/widgets/ingredient_row.dart';
import 'package:kuktam/recipes/presentation/widgets/web_import_review.dart';
import 'package:kuktam/recipes/presentation/widgets/web_import_review_controller.dart';
import 'package:kuktam/recipes/domain/services/web_recipe_import_service.dart';
import 'web_import_editor_review_test.dart' as fixtures;

class _Repo implements RecipeRepository {
  int checks = 0;
  Recipe? saved;
  @override
  Future<bool> recipeNameExists({
    required String name,
    String? excludedRecipeId,
  }) async {
    checks++;
    return false;
  }

  @override
  Future<void> saveRecipe(Recipe recipe) async {
    saved = recipe;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _open(
  WidgetTester t,
  _Repo repo,
  WebRecipeImportHandoff handoff,
) async {
  // Keep the small fixture and Save visible; layout regressions have separate tests.
  await t.binding.setSurfaceSize(const Size(900, 1800));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AddRecipeScreen(
                  initialImport: handoff,
                  webImport: handoff,
                  recipeRepository: repo,
                ),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('Open'));
  await t.pumpAndSettle();
}

Future<void> _save(WidgetTester t) async {
  await t.ensureVisible(find.text('Mentés'));
  await t.tap(find.text('Mentés'));
  await t.pumpAndSettle();
}

Future<void> _acceptRows(WidgetTester t) async {
  // Each issue has its own real UI action: no global acceptance.
  while (find
      .widgetWithText(TextButton, 'Ellenőriztem')
      .evaluate()
      .isNotEmpty) {
    final action = find.widgetWithText(TextButton, 'Ellenőriztem').first;
    await t.ensureVisible(action);
    await t.tap(action);
    await t.pump();
  }
}

void main() {
  testWidgets('unresolved row blocks before repository; accepted row saves', (
    t,
  ) async {
    final repo = _Repo();
    await _open(t, repo, fixtures.draft());
    final row = t.widget<IngredientRow>(find.byType(IngredientRow).first);
    final element = t.element(find.byType(IngredientRow).first);
    await _save(t);
    expect(repo.checks, 0);
    expect(repo.saved, isNull);
    expect(
      find.text('Mentés előtt ellenőrizd a megjelölt importált adatokat.'),
      findsOneWidget,
    );
    expect(
      identical(t.element(find.byType(IngredientRow).first), element),
      true,
    );
    expect(
      identical(t.widget<IngredientRow>(find.byType(IngredientRow).first), row),
      true,
    );
    await _acceptRows(t);
    await _save(t);
    expect(repo.checks, 1);
    expect(repo.saved, isNotNull);
  });

  testWidgets('acceptance invalidation blocks again; correction then saves', (
    t,
  ) async {
    final repo = _Repo();
    await _open(t, repo, fixtures.draft());
    await _acceptRows(t);
    final row = t.widget<IngredientRow>(find.byType(IngredientRow).first);
    row.data.amountController.text = '3';
    await t.pump();
    await _save(t);
    expect(repo.checks, 0);
    row.data.nameController.text = 'olaj';
    row.data.selectedUnit = 'ml';
    row.onUnitChanged!();
    await t.pump();
    await _save(t);
    expect(repo.saved?.ingredients.first.name, 'olaj');
  });

  testWidgets('deleting warned row clears gate without accepting', (t) async {
    final repo = _Repo();
    await _open(t, repo, fixtures.draft());
    await t.tap(find.byTooltip('Hozzávaló törlése').first);
    await t.pumpAndSettle();
    await _save(t);
    expect(repo.saved?.ingredients.single.name, 'alma');
  });

  for (final host in ['nosalty.hu', 'unknown.example']) {
    testWidgets('$host mandatory recipe acceptance gates Save', (t) async {
      final repo = _Repo();
      await _open(t, repo, fixtures.draft(host: host, rows: ['1 db alma']));
      await _save(t);
      expect(repo.checks, 0);
      expect(
        find.text(
          'Mentés előtt erősítsd meg, hogy ellenőrizted az importált receptet.',
        ),
        findsOneWidget,
      );
      final action = find.descendant(
        of: find.byType(WebImportReviewBanner),
        matching: find.byType(TextButton),
      );
      await t.ensureVisible(action);
      await t.tap(action);
      await t.pump();
      await _save(t);
      expect(repo.saved, isNotNull);
    });
  }

  testWidgets('PASS saves without extra acceptance', (t) async {
    final repo = _Repo();
    await _open(t, repo, fixtures.draft(rows: ['1 db alma']));
    expect(find.byType(WebReviewIssueTile), findsNothing);
    await _save(t);
    expect(repo.saved, isNotNull);
  });

  testWidgets(
    'accepted review cannot bypass normal name or quantity validation',
    (t) async {
      final repo = _Repo();
      await _open(t, repo, fixtures.draft());
      await _acceptRows(t);
      final title = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Recept neve',
      );
      await t.enterText(title, '');
      await _save(t);
      expect(repo.checks, 0);
      expect(find.text('Add meg a recept nevét!'), findsOneWidget);
      await t.pump(const Duration(seconds: 5));
      await t.pumpAndSettle();
      await t.enterText(title, 'Teszt');
      t
              .widget<IngredientRow>(find.byType(IngredientRow).first)
              .data
              .amountController
              .text =
          '0';
      await t.pump();
      await _save(t);
      expect(repo.checks, 0);
      expect(
        find.text('Minden hozzávalónál adj meg érvényes, pozitív mennyiséget!'),
        findsOneWidget,
      );
    },
  );

  for (final severity in [WebImportSeverity.info, WebImportSeverity.blocking]) {
    testWidgets('$severity gate enforced independently of valid fields', (
      t,
    ) async {
      final clean = fixtures.draft(rows: ['1 db alma']);
      final meta = clean.result.review!;
      final original = meta.rows.single;
      final issue = WebImportIssue(
        WebImportIssueCode.invalidIngredient,
        severity,
        rowId: original.id,
      );
      final review = RecipeImportReviewMetadata(
        title: meta.title,
        preparation: meta.preparation,
        rows: [
          WebIngredientReview(
            id: original.id,
            original: original.original,
            value: original.value,
            issues: [issue],
          ),
        ],
      );
      final handoff = WebRecipeImportHandoff(
        result: WebRecipeImportResult(
          quality: clean.result.quality,
          draft: clean.result.draft,
          review: review,
          normalized: clean.result.normalized,
        ),
        originalUrl: clean.originalUrl,
        finalUrl: clean.finalUrl,
      );
      final repo = _Repo();
      await _open(t, repo, handoff);
      expect(find.widgetWithText(TextButton, 'Ellenőriztem'), findsNothing);
      await _save(t);
      if (severity == WebImportSeverity.info) {
        expect(repo.saved, isNotNull);
      } else {
        expect(repo.checks, 0);
        expect(repo.saved, isNull);
        expect(
          find.text('Javítsd a hibás importált adatokat a mentéshez.'),
          findsOneWidget,
        );
      }
    });
  }

  test(
    'blocking cannot be accepted; correction removes gate; INFO never blocks',
    () {
      final meta = fixtures.draft(rows: ['1 db alma']).result.review!;
      const blocking = WebImportIssue(
        WebImportIssueCode.invalidIngredient,
        WebImportSeverity.blocking,
        rowId: 'test:0',
      );
      final original = meta.rows.single;
      final row = WebIngredientReview(
        id: original.id,
        original: original.original,
        value: original.value,
        issues: [blocking],
      );
      final c = WebImportReviewController(
        RecipeImportReviewMetadata(
          title: meta.title,
          preparation: meta.preparation,
          rows: [row],
        ),
      );
      final data = IngredientRowData(name: 'alma', quantity: '1', unit: 'db');
      c.watch(data, id: row.id);
      expect(
        c.saveBlockMessage,
        'Javítsd a hibás importált adatokat a mentéshez.',
      );
      c.acceptRow(row.id, blocking);
      expect(c.saveBlockMessage, isNotNull);
      data.nameController.text = 'körte';
      expect(c.saveBlockMessage, isNull);
      c.dispose();
      data.dispose();
      final info = WebImportReviewController(
        RecipeImportReviewMetadata(
          title: meta.title,
          preparation: meta.preparation,
          rows: meta.rows,
          issues: [
            const WebImportIssue(
              WebImportIssueCode.sourceStructureWarning,
              WebImportSeverity.info,
            ),
          ],
        ),
      );
      expect(info.saveBlockMessage, isNull);
      info.dispose();
    },
  );

  test(
    'long import gate is read-only: no signals, revisions or controller churn',
    () {
      final meta = fixtures
          .draft(rows: List.generate(40, (_) => '2 tbsp olaj'))
          .result
          .review!;
      final c = WebImportReviewController(meta);
      final data = <IngredientRowData>[];
      var notifications = 0;
      c.metadata.addListener(() => notifications++);
      for (final r in meta.rows) {
        final d = IngredientRowData(
          name: r.value.name,
          quantity: '2',
          unit: 'db',
        );
        data.add(d);
        c.watch(d, id: r.id);
        c.signal(r.id).addListener(() => notifications++);
        for (final issue in r.issues) {
          c.acceptRow(r.id, issue);
        }
      }
      final revision = c.revision;
      final before = notifications;
      final controllers = data.map((d) => d.amountController).toList();
      for (var i = 0; i < 100; i++) {
        expect(c.saveBlockMessage, isNull);
      }
      expect(notifications, before);
      expect(c.revision, revision);
      expect(data.map((d) => d.amountController), orderedEquals(controllers));
      data.last.amountController.text = '3';
      expect(c.saveBlockMessage, isNotNull);
      c.remove(data.last);
      expect(c.saveBlockMessage, isNull);
      c.dispose();
      for (final d in data) {
        d.dispose();
      }
    },
  );
}
