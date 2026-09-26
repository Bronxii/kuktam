import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/home/presentation/screens/main_screen.dart';
import 'package:kuktam/recipes/data/repositories/recipe_repository.dart';
import 'package:kuktam/shopping/data/repositories/shopping_repository.dart';
import 'package:kuktam/recipes/data/services/web_recipe_fetcher.dart';
import 'package:kuktam/recipes/data/services/web_recipe_import_loader.dart';
import 'package:kuktam/recipes/domain/models/recipe.dart';
import 'package:kuktam/recipes/domain/models/web_import_issue.dart';
import 'package:kuktam/recipes/domain/models/web_import_quality.dart';
import 'package:kuktam/recipes/domain/models/web_recipe_import_handoff.dart';
import 'package:kuktam/recipes/presentation/screens/add_recipe_screen.dart';
import 'package:kuktam/recipes/presentation/widgets/ingredient_row.dart';
import 'package:kuktam/recipes/presentation/widgets/web_import_review.dart';

class _Repo implements RecipeRepository {
  final saved = <Recipe>[];
  int checks = 0;
  Completer<void>? pending;
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
    saved.add(recipe);
    await pending?.future;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Shopping implements ShoppingRepository {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Transport implements WebFetchTransport {
  String body;
  int status = 200, calls = 0;
  Object? error;
  Completer<WebFetchResponse>? pending;
  _Transport(this.body);
  @override
  Future<WebFetchResponse> get(
    Uri uri,
    InternetAddress address,
    WebImportCancellation token,
  ) async {
    calls++;
    if (error != null) throw error!;
    if (pending != null) return pending!.future;
    return response();
  }

  WebFetchResponse response() => WebFetchResponse(status, {
    'content-type': 'text/html; charset=utf-8',
  }, Stream.value(utf8.encode(body)));
  @override
  void close() {}
}

String local(String name) =>
    File('test/fixtures/web_import_integration/$name.html').readAsStringSync();
String snapshot(String id) =>
    File('tool/web_import_poc/results/html/p1_$id.html').readAsStringSync();
final input = find.byKey(const ValueKey('recipe-import-text'));
final process = find.widgetWithText(FilledButton, 'Feldolgozás');

class _Harness {
  final repo = _Repo();
  final _Transport transport;
  late final WebRecipeImportLoader loader;
  final results = <WebRecipeImportHandoff>[];
  final ids = <String>[];
  bool dnsFails = false;
  Future<WebRecipeImportHandoff>? operation;
  _Harness(String html) : transport = _Transport(html) {
    loader = WebRecipeImportLoader(
      fetcher: WebRecipeFetcher(
        transport: () => transport,
        resolve: (_) async {
          if (dnsFails) throw const SocketException('private DNS detail');
          return [InternetAddress('8.8.8.8')];
        },
      ),
    );
  }
  Future<void> open(WidgetTester t, {double height = 5000}) async {
    await t.binding.setSurfaceSize(Size(1000, height));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      MaterialApp(
        home: MainScreen(
          tabBodies: const [Text('recipes'), Text('shopping'), Text('cook')],
          recipeRepository: repo,
          shoppingRepository: _Shopping(),
          importWeb: (url, {required cancellation, required importId}) async {
            ids.add(importId);
            operation = loader.load(
              url,
              cancellation: cancellation,
              importId: importId,
            );
            final r = await operation!;
            results.add(r);
            return r;
          },
        ),
      ),
    );
    await t.tap(find.byTooltip('Recept importálása'));
    await t.pumpAndSettle();
  }

  Future<void> submit(WidgetTester t, String value) async {
    await t.enterText(input, value);
    await t.pump();
    await t.ensureVisible(process);
    await perform(t);
  }

  Future<void> perform(WidgetTester t) async {
    await t.runAsync(() async {
      await t.tap(process);
      await operation?.then<void>((_) {}, onError: (Object e, StackTrace s) {});
    });
    await t.pumpAndSettle();
  }

  Future<void> editor(WidgetTester t) async {
    final next = find.widgetWithText(FilledButton, 'Tovább a szerkesztőbe');
    if (next.evaluate().isNotEmpty) {
      await t.ensureVisible(next);
      await t.tap(next);
      await t.pumpAndSettle();
    }
    expect(
      find.byType(AddRecipeScreen),
      findsOneWidget,
      reason: input.evaluate().isEmpty
          ? 'no dialog'
          : t.widget<TextField>(input).decoration?.errorText,
    );
    expect(
      repo.saved,
      isEmpty,
      reason: 'Import and handoff must never autosave',
    );
  }
}

Future<void> reveal(WidgetTester t, Finder f) async {
  if (f.evaluate().isEmpty) {
    await t.scrollUntilVisible(
      f,
      350,
      scrollable: find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first,
      maxScrolls: 100,
    );
  }
  await t.ensureVisible(f);
  await t.pumpAndSettle();
}

Future<void> save(WidgetTester t) async {
  await reveal(t, find.text('Mentés'));
  await t.tap(find.text('Mentés'));
  await t.pumpAndSettle();
}

Future<void> acceptRows(WidgetTester t) async {
  // Tests invoke each separate visible action, never a bulk domain acceptance.
  for (var n = 0; n < 100; n++) {
    final f = find.widgetWithText(TextButton, 'Ellenőriztem');
    if (f.evaluate().isEmpty) return;
    await reveal(t, f.first);
    await t.tap(f.first);
    await t.pump();
  }
  fail('Unexpected acceptance loop');
}

void _assertPayload(_Harness h) {
  expect(h.repo.saved.length, 1);
  final recipe = h.repo.saved.single;
  final draft = h.results.single.result.draft!;
  expect(recipe.name, draft.title);
  expect(recipe.preparation, draft.preparationText);
  expect(recipe.spices, isEmpty);
  expect(
    recipe.toMap().keys,
    unorderedEquals(['name', 'ingredients', 'spices', 'preparation']),
  );
  for (final row in recipe.toMap()['ingredients'] as List) {
    expect((row as Map).keys, unorderedEquals(['name', 'quantity', 'unit']));
  }
}

void main() {
  testWidgets(
    'saved Mindmegette snapshot: complete production path, payload and double Save',
    (t) async {
      final h = _Harness(snapshot('01'));
      await h.open(t);
      await h.submit(t, 'https://www.mindmegette.hu/recept/rakott-krumpli');
      await h.editor(t);
      expect(
        h.results.single.result.review!.issues.where(
          (i) => i.severity == WebImportSeverity.review,
        ),
        isEmpty,
      );
      await acceptRows(t);
      h.repo.pending = Completer<void>();
      await reveal(t, find.text('Mentés'));
      final action = t
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Mentés'))
          .onPressed!;
      action();
      action();
      await t.pump();
      expect(h.repo.saved.length, 1);
      h.repo.pending!.complete();
      await t.pumpAndSettle();
      _assertPayload(h);
      final r = h.repo.saved.single;
      expect(r.name, 'Rakott krumpli');
      expect(r.ingredients.map((i) => (i.name, i.quantity, i.unit)).toList(), [
        ('Burgonya', 1.0, 'kg'),
        ('Tojás', 6.0, 'db'),
        ('Só', 1.0, 'db'),
        ('Kolbász', 100.0, 'g'),
        ('Tejföl', 500.0, 'ml'),
        ('Tojássárgája', 2.0, 'db'),
        ('Vaj', 2.0, 'tk'),
        ('Bacon', 100.0, 'g'),
      ]);
      expect(r.preparation, contains('10-15 percre'));
      expect(r.preparation, isNot(contains('&nbsp;')));
      expect(h.transport.calls, 1);
    },
  );

  testWidgets(
    'saved Nosalty: source quantity preserved, blocking correction and mandatory notice',
    (t) async {
      final h = _Harness(snapshot('07'));
      await h.open(t);
      await h.submit(t, 'https://www.nosalty.hu/recept/palacsinta-alaprecept');
      await h.editor(t);
      final result = h.results.single;
      expect(result.result.quality.quality, WebImportQuality.review);
      expect(
        result.result.review!.issues.map((i) => i.code),
        contains(WebImportIssueCode.knownSourceRisk),
      );
      final rows = t
          .widgetList<IngredientRow>(find.byType(IngredientRow))
          .toList();
      expect(rows.length, 7);
      expect(result.result.review!.rows.last.original.rawText, startsWith('0'));
      expect(rows.last.data.amountController.text, '0');
      await save(t);
      expect(h.repo.saved, isEmpty);
      rows.last.data.amountController.text = '1';
      await t.pump();
      await acceptRows(t);
      await save(t);
      expect(h.repo.saved, isEmpty, reason: 'Recipe-level review is mandatory');
      final accept = find.widgetWithText(
        TextButton,
        'A mennyiségeket ellenőriztem.',
      );
      await reveal(t, accept);
      await t.tap(accept);
      await t.pump();
      expect(h.repo.saved, isEmpty);
      await save(t);
      _assertPayload(h);
      expect(h.repo.saved.single.ingredients.last.quantity, 1);
    },
  );

  testWidgets(
    'unknown source generic import requires acceptance and saves clean quantities',
    (t) async {
      final h = _Harness(local('clean'));
      await h.open(t);
      await h.submit(t, 'https://unknown.example/recipe');
      await h.editor(t);
      expect(
        h.results.single.result.review!.issues.map((i) => i.code),
        contains(WebImportIssueCode.unverifiedSource),
      );
      await save(t);
      expect(h.repo.checks, 0);
      final action = find.widgetWithText(
        TextButton,
        'Ellenőriztem az importált receptet.',
      );
      await reveal(t, action);
      await t.tap(action);
      await t.pump();
      await save(t);
      _assertPayload(h);
      expect(
        h.repo.saved.single.ingredients
            .map((i) => (i.name, i.quantity, i.unit))
            .toList(),
        [('alma', 500.0, 'g'), ('tej', 200.0, 'ml')],
      );
    },
  );

  testWidgets(
    'multiple row reviews, raw evidence, invalidation, own-row deletion and correction',
    (t) async {
      final h = _Harness(local('review'));
      await h.open(t);
      await h.submit(t, 'https://mindmegette.hu/recipe');
      await h.editor(t);
      final meta = h.results.single.result.review!;
      expect(meta.rows.map((r) => r.id).toSet().length, 3);
      expect(
        meta.rows.first.issues.map((i) => i.code),
        contains(WebImportIssueCode.silentDbFallbackRisk),
      );
      await t.tap(find.text('Eredeti sor').first);
      await t.pumpAndSettle();
      expect(find.text('2 tbsp olive oil'), findsOneWidget);
      final first = find.byType(IngredientImportWarning).first;
      while (find
          .descendant(
            of: first,
            matching: find.widgetWithText(TextButton, 'Ellenőriztem'),
          )
          .evaluate()
          .isNotEmpty) {
        await t.tap(
          find
              .descendant(
                of: first,
                matching: find.widgetWithText(TextButton, 'Ellenőriztem'),
              )
              .first,
        );
        await t.pump();
      }
      await save(t);
      expect(h.repo.saved, isEmpty);
      await acceptRows(t);
      final row = t.widget<IngredientRow>(find.byType(IngredientRow).first);
      row.data.amountController.text = '3';
      await t.pump();
      await save(t);
      expect(h.repo.saved, isEmpty);
      // Remove only the second imported row; first still blocks.
      await reveal(t, find.byTooltip('Hozzávaló törlése').at(1));
      await t.tap(find.byTooltip('Hozzávaló törlése').at(1));
      await t.pumpAndSettle();
      await save(t);
      expect(h.repo.saved, isEmpty);
      row.data.nameController.text = 'olívaolaj';
      row.data.selectedUnit = 'ml';
      row.onUnitChanged!();
      await t.pump();
      await save(t);
      _assertPayload(h);
      expect(h.repo.saved.single.ingredients.map((i) => i.name), [
        'olívaolaj',
        'alma',
      ]);
    },
  );

  testWidgets(
    'blocking row cannot be accepted; corrected quantity permits save',
    (t) async {
      final h = _Harness(local('blocking'));
      await h.open(t);
      await h.submit(t, 'https://mindmegette.hu/recipe');
      await h.editor(t);
      final blocking = t
          .widgetList<WebReviewIssueTile>(find.byType(WebReviewIssueTile))
          .where((w) => w.issue.severity == WebImportSeverity.blocking);
      expect(blocking, isNotEmpty);
      for (final tile in blocking) {
        expect(
          find.descendant(
            of: find.byWidget(tile),
            matching: find.byType(TextButton),
          ),
          findsNothing,
        );
      }
      await save(t);
      expect(h.repo.saved, isEmpty);
      t
              .widget<IngredientRow>(find.byType(IngredientRow).first)
              .data
              .amountController
              .text =
          '100';
      await t.pump();
      await acceptRows(t);
      await save(t);
      _assertPayload(h);
      expect(h.repo.saved.single.ingredients.first.quantity, 100);
    },
  );

  testWidgets(
    'text import shares dialog but never fetches; explicit Save only',
    (t) async {
      final h = _Harness(local('clean'));
      await h.open(t);
      await h.submit(
        t,
        'Alma\nHozzávalók:\n500 g alma\nElkészítés:\nFőzd meg.',
      );
      await h.editor(t);
      expect(
        t.widget<AddRecipeScreen>(find.byType(AddRecipeScreen)).webImport,
        isNull,
      );
      expect(find.byType(WebImportReviewBanner), findsNothing);
      expect(h.transport.calls, 0);
      await save(t);
      expect(h.repo.saved.single.name, 'Alma');
      expect(h.repo.saved.single.ingredients.single.quantity, 500);
    },
  );

  testWidgets('accepted review followed by Back/discard never saves', (
    t,
  ) async {
    final h = _Harness(local('review'));
    await h.open(t);
    await h.submit(t, 'https://mindmegette.hu/recipe');
    await h.editor(t);
    await acceptRows(t);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('Kilépés mentés nélkül?'), findsOneWidget);
    await t.tap(find.text('Kilépés'));
    await t.pumpAndSettle();
    expect(h.repo.saved, isEmpty);
    expect(find.byType(AddRecipeScreen), findsNothing);
  });

  for (final scenario in [
    '403',
    '404',
    '429',
    '500',
    'timeout',
    'dns',
    'connect',
    'no-json',
    'bad-json',
    'no-recipe',
    'invalid',
    'multiple',
  ]) {
    testWidgets(
      '$scenario full flow fails safely then retries into editor and Save',
      (t) async {
        final h = _Harness(local('clean'));
        final status = int.tryParse(scenario);
        if (status != null) h.transport.status = status;
        if (scenario == 'timeout') {
          h.transport.error = TimeoutException('private');
        }
        if (scenario == 'dns') h.dnsFails = true;
        if (scenario == 'connect') {
          h.transport.error = const SocketException('private');
        }
        if (scenario == 'no-json') h.transport.body = '<html>none</html>';
        if (scenario == 'bad-json') {
          h.transport.body = '<script type="application/ld+json">{</script>';
        }
        if (scenario == 'no-recipe') {
          h.transport.body =
              '<script type="application/ld+json">{"@type":"Person"}</script>';
        }
        if (scenario == 'invalid') {
          h.transport.body =
              '<script type="application/ld+json">{"@type":"Recipe"}</script>';
        }
        if (scenario == 'multiple') {
          h.transport.body = local('clean') + local('clean');
        }
        await h.open(t);
        await h.submit(t, 'https://mindmegette.hu/recipe');
        expect(find.byType(AddRecipeScreen), findsNothing);
        expect(h.repo.checks, 0);
        expect(h.repo.saved, isEmpty);
        expect(
          t.widget<TextField>(input).controller!.text,
          'https://mindmegette.hu/recipe',
        );
        expect(t.widget<TextField>(input).decoration!.errorText, isNotNull);
        h.transport.status = 200;
        h.transport.error = null;
        h.dnsFails = false;
        h.transport.body = local('clean');
        await t.ensureVisible(process);
        await h.perform(t);
        await h.editor(t);
        expect(h.ids.toSet().length, 2);
        await save(t);
        _assertPayload(h);
      },
    );
  }

  for (final back in [false, true]) {
    testWidgets('full pipeline cancel/back=$back ignores late response', (
      t,
    ) async {
      final h = _Harness(local('clean'));
      h.transport.pending = Completer<WebFetchResponse>();
      await h.open(t);
      await t.enterText(input, 'https://mindmegette.hu/recipe');
      await t.pump();
      await t.tap(process);
      await t.pump();
      if (back) {
        await t.binding.handlePopRoute();
      } else {
        await t.tap(find.byTooltip('Bezárás'));
      }
      await t.pumpAndSettle();
      await t.tap(find.text('Kilépés'));
      await t.pumpAndSettle();
      h.transport.pending!.complete(h.transport.response());
      await t.pumpAndSettle();
      expect(h.repo.saved, isEmpty);
      expect(find.byType(AddRecipeScreen), findsNothing);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('manual New Recipe saves without web state', (t) async {
    final h = _Harness(local('clean'));
    await h.open(t);
    await t.tap(find.byTooltip('Bezárás'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Új recept'));
    await t.pumpAndSettle();
    Finder field(String label) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
    );
    await t.enterText(field('Recept neve'), 'Kézi alma');
    final row = t.widget<IngredientRow>(find.byType(IngredientRow).first);
    row.data.nameController.text = 'alma';
    row.data.amountController.text = '500';
    await t.enterText(field('Elkészítés menete'), 'Főzd.');
    expect(find.byType(WebReviewIssueTile), findsNothing);
    await save(t);
    expect(h.repo.saved.single.name, 'Kézi alma');
    expect(h.repo.saved.single.ingredients.single.quantity, 500);
    expect(h.repo.saved.single.preparation, 'Főzd.');
    expect(h.transport.calls, 0);
  });

  testWidgets(
    'long saved snapshot scroll: stable rows, individual reviews, gate and payload',
    (t) async {
      final h = _Harness(snapshot('03'));
      await h.open(t, height: 900);
      await h.submit(t, 'https://mindmegette.hu/recept/husleves');
      await h.editor(t);
      final meta = h.results.single.result.review!;
      expect(meta.rows.length, 14);
      expect(
        meta.rows.where((r) => r.issues.isNotEmpty).length,
        greaterThan(3),
      );
      final firstController = t
          .widget<IngredientRow>(find.byType(IngredientRow).first)
          .data
          .amountController;
      for (final row in meta.rows) {
        final warning = find.byKey(ValueKey('web-review-${row.id}'));
        await reveal(t, warning);
        final actions = find.descendant(
          of: warning,
          matching: find.widgetWithText(TextButton, 'Ellenőriztem'),
        );
        while (actions.evaluate().isNotEmpty) {
          await reveal(t, actions.first);
          await t.tap(actions.first);
          await t.pump();
        }
        expect(h.repo.saved, isEmpty);
      }
      final scroll = t.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      scroll.position.jumpTo(0);
      await t.pumpAndSettle();
      expect(
        identical(
          t
              .widget<IngredientRow>(find.byType(IngredientRow).first)
              .data
              .amountController,
          firstController,
        ),
        true,
      );
      await save(t);
      _assertPayload(h);
      expect(h.repo.saved.single.ingredients.length, 14);
      expect(h.repo.saved.single.ingredients.first.name, 'színhús');
      expect(h.repo.saved.single.ingredients.last.name, 'levelestészta');
      expect(t.takeException(), isNull);
    },
  );

  test('quality matrix runs production fetch/loader/gate offline', () async {
    for (final entry in [
      ('mindmegette.hu', 'clean', WebImportQuality.pass),
      ('nosalty.hu', 'clean', WebImportQuality.review),
      ('unknown.example', 'clean', WebImportQuality.review),
      ('mindmegette.hu', 'review', WebImportQuality.review),
      ('mindmegette.hu', 'blocking', WebImportQuality.review),
    ]) {
      final h = _Harness(local(entry.$2));
      final result = await h.loader.load(
        'https://${entry.$1}/recipe',
        cancellation: WebImportCancellation(),
        importId: 'matrix',
      );
      expect(result.result.quality.quality, entry.$3);
      if (entry.$2 == 'blocking') {
        expect(
          result.result.review!.unresolved.any(
            (i) => i.severity == WebImportSeverity.blocking,
          ),
          true,
        );
      }
    }
  });
}
