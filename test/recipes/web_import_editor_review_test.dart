import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/recipes/data/repositories/recipe_repository.dart';
import 'package:kuktam/recipes/domain/models/web_import_issue.dart';
import 'package:kuktam/recipes/domain/models/web_recipe_import_handoff.dart';
import 'package:kuktam/recipes/domain/services/recipe_json_ld_extractor.dart';
import 'package:kuktam/recipes/domain/services/web_recipe_import_service.dart';
import 'package:kuktam/recipes/presentation/screens/add_recipe_screen.dart';
import 'package:kuktam/recipes/presentation/widgets/ingredient_row.dart';
import 'package:kuktam/recipes/presentation/widgets/web_import_review.dart';
import 'package:kuktam/recipes/presentation/widgets/web_import_review_controller.dart';

class Repo implements RecipeRepository {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

WebRecipeImportHandoff draft({
  String host = 'mindmegette.hu',
  List<String> rows = const ['2 tbsp olaj', '1 db alma'],
}) {
  final result = const WebRecipeImportService().prepare(
    extractRecipes(
      '<script type="application/ld+json">${jsonEncode({'@type': 'Recipe', 'name': 'Teszt', 'recipeIngredient': rows, 'recipeInstructions': 'Főzd.'})}</script>',
    ),
    sourceUrl: Uri.parse('https://$host'),
    importId: 'test',
  );
  return WebRecipeImportHandoff(
    result: result,
    originalUrl: 'https://$host',
    finalUrl: Uri.parse('https://$host'),
  );
}

void main() {
  test(
    'issue-level acceptance, BLOCKING protection, targeted invalidation and stable deletion',
    () {
      final meta = draft(
        rows: ['2 tbsp olaj', '2 gerezd fokhagyma'],
      ).result.review!;
      final c = WebImportReviewController(meta);
      final a = IngredientRowData(
        name: meta.rows[0].value.name,
        quantity: '2',
        unit: 'db',
      );
      final b = IngredientRowData(
        name: meta.rows[1].value.name,
        quantity: '2',
        unit: 'db',
      );
      c.watch(a, id: 'test:0');
      c.watch(b, id: 'test:1');
      var bChanges = 0;
      c.signal('test:1').addListener(() => bChanges++);
      final issue = c.signal('test:0').value.issues.first;
      c.acceptRow('test:0', issue);
      expect(c.signal('test:0').value.isAccepted(issue), true);
      expect(c.signal('test:0').value.unresolved, isNotEmpty); // not accept-all
      a.amountController.text = '3';
      expect(c.signal('test:0').value.accepted, false);
      expect(bChanges, 0);
      a.nameController.text = 'olaj';
      a.selectedUnit = 'ml';
      c.update(a);
      expect(c.signal('test:0').value.issues, isEmpty);
      c.remove(a);
      expect(c.metadata.value.rows.single.id, 'test:1');
      expect(c.idFor(b), 'test:1');
      final manual = IngredientRowData();
      c.added(manual);
      expect(c.idFor(manual), isNull);
      expect(c.metadata.value.rows.length, 1);
      b.amountController.text = '0';
      final blocked = c
          .signal('test:1')
          .value
          .issues
          .firstWhere((i) => i.severity == WebImportSeverity.blocking);
      c.acceptRow('test:1', blocked);
      expect(c.signal('test:1').value.isAccepted(blocked), false);
      c.dispose();
      a.dispose();
      b.dispose();
      manual.dispose();
    },
  );
  test(
    'recipe acceptance dirty revision, edits invalidate and manually added rows have no metadata',
    () {
      final c = WebImportReviewController(
        draft(host: 'nosalty.hu', rows: ['1 db alma']).result.review!,
      );
      final row = IngredientRowData(name: 'alma', quantity: '1', unit: 'db');
      c.watch(row, id: 'test:0');
      final issue = c.metadata.value.issues.single;
      final before = c.revision;
      c.acceptRecipe(issue);
      expect(c.revision, greaterThan(before));
      expect(c.metadata.value.isRecipeIssueAccepted(issue), true);
      c.contentChanged('Más cím', 'Főzd.');
      expect(c.metadata.value.isRecipeIssueAccepted(issue), false);
      c.acceptRecipe(issue);
      final manual = IngredientRowData();
      c.added(manual);
      expect(c.metadata.value.isRecipeIssueAccepted(issue), false);
      c.acceptRecipe(issue);
      manual.nameController.text = 'új';
      expect(c.metadata.value.isRecipeIssueAccepted(issue), false);
      c.dispose();
      row.dispose();
      manual.dispose();
    },
  );
  Future<void> open(WidgetTester t, WebRecipeImportHandoff d) async {
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('Open'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AddRecipeScreen(
                    initialImport: d,
                    webImport: d,
                    recipeRepository: Repo(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Open'));
    await t.pumpAndSettle();
  }

  testWidgets(
    'row warnings, raw source, per-issue acceptance and controller identity',
    (t) async {
      await open(t, draft());
      expect(find.textContaining('nem támogatott'), findsOneWidget);
      expect(find.textContaining('félrevezető'), findsOneWidget);
      final row = t.widget<IngredientRow>(find.byType(IngredientRow).first);
      final controller = row.data.amountController;
      final first = find.byType(IngredientImportWarning).first;
      final accept = find
          .descendant(
            of: first,
            matching: find.widgetWithText(TextButton, 'Ellenőriztem'),
          )
          .first;
      await t.ensureVisible(accept);
      await t.tap(accept);
      await t.pump();
      expect(find.textContaining('Ellenőrizve:'), findsOneWidget);
      expect(
        identical(
          t
              .widget<IngredientRow>(find.byType(IngredientRow).first)
              .data
              .amountController,
          controller,
        ),
        true,
      );
      final raw = find.descendant(
        of: first,
        matching: find.text('Eredeti sor'),
      );
      await t.ensureVisible(raw);
      await t.tap(raw);
      await t.pumpAndSettle();
      expect(find.text('2 tbsp olaj'), findsOneWidget);
      controller.text = '3';
      await t.pump();
      expect(find.textContaining('Ellenőrizve:'), findsNothing);
    },
  );
  testWidgets(
    'field correction clears issues; deletion uses row identity; manual addition clean',
    (t) async {
      await open(t, draft());
      final data = t
          .widget<IngredientRow>(find.byType(IngredientRow).first)
          .data;
      data.nameController.text = 'olaj';
      data.selectedUnit = 'ml';
      t
          .widget<IngredientRow>(find.byType(IngredientRow).first)
          .onUnitChanged!();
      await t.pump();
      expect(find.textContaining('nem támogatott'), findsNothing);
      expect(find.textContaining('félrevezető'), findsNothing);
      final delete = find.byTooltip('Hozzávaló törlése').first;
      await t.ensureVisible(delete);
      await t.tap(delete);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('web-review-test:0')), findsNothing);
      expect(find.byKey(const ValueKey('web-review-test:1')), findsOneWidget);
      final add = find.text('Hozzávaló hozzáadása');
      await t.ensureVisible(add);
      await t.tap(add);
      await t.pumpAndSettle();
      expect(find.byType(IngredientImportWarning), findsOneWidget);
    },
  );
  testWidgets('BLOCKING issue offers no acceptance', (t) async {
    await open(t, draft(rows: ['0 g liszt', '1 db alma']));
    expect(find.textContaining('Javítandó:'), findsWidgets);
    final tiles = t
        .widgetList<WebReviewIssueTile>(find.byType(WebReviewIssueTile))
        .where((w) => w.issue.severity == WebImportSeverity.blocking);
    expect(tiles, isNotEmpty);
    for (final tile in tiles) {
      expect(
        find.descendant(
          of: find.byWidget(tile),
          matching: find.byType(TextButton),
        ),
        findsNothing,
      );
    }
  });
  for (final host in ['nosalty.hu', 'unknown.example']) {
    testWidgets('$host notice acceptance and dirty Back', (t) async {
      await open(t, draft(host: host, rows: ['1 db alma']));
      final banner = find.byType(WebImportReviewBanner);
      final accept = find.descendant(
        of: banner,
        matching: find.byType(TextButton),
      );
      expect(accept, findsOneWidget);
      await t.tap(accept);
      await t.pump();
      expect(
        find.descendant(
          of: banner,
          matching: find.textContaining('Ellenőrizve:'),
        ),
        findsOneWidget,
      );
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('Kilépés mentés nélkül?'), findsOneWidget);
      await t.tap(find.text('Mégsem'));
      await t.pumpAndSettle();
      expect(find.byType(AddRecipeScreen), findsOneWidget);
    });
  }
  testWidgets('known PASS has no unnecessary recipe notice', (t) async {
    await open(t, draft(rows: ['1 db alma']));
    expect(find.byType(WebReviewIssueTile), findsNothing);
  });
}
