import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/recipes/data/services/web_recipe_fetcher.dart';
import 'package:kuktam/recipes/data/services/web_recipe_import_loader.dart';
import 'package:kuktam/recipes/domain/models/recipe_import_draft.dart';
import 'package:kuktam/recipes/domain/models/web_import_issue.dart';
import 'package:kuktam/recipes/domain/models/web_recipe_import_handoff.dart';
import 'package:kuktam/recipes/domain/services/recipe_json_ld_extractor.dart';
import 'package:kuktam/recipes/domain/services/web_recipe_import_service.dart';
import 'package:kuktam/recipes/presentation/widgets/recipe_import_dialog.dart';
import 'package:kuktam/recipes/presentation/widgets/web_import_error_message.dart';
import 'package:kuktam/recipes/presentation/screens/add_recipe_screen.dart';
import 'package:kuktam/home/presentation/screens/main_screen.dart';
import 'package:kuktam/recipes/data/repositories/recipe_repository.dart';
import 'package:kuktam/shopping/data/repositories/shopping_repository.dart';

String htmlRecipe({List<String> rows = const ['1 db alma']}) =>
    '<script type="application/ld+json">${jsonEncode({'@type': 'Recipe', 'name': 'Alma', 'recipeIngredient': rows, 'recipeInstructions': 'Főzd meg.'})}</script>';
WebRecipeImportHandoff handoff({
  String host = 'mindmegette.hu',
  String id = 'op',
  List<String> rows = const ['1 db alma'],
}) {
  final url = Uri.parse('https://$host/recept');
  final result = const WebRecipeImportService().prepare(
    extractRecipes(htmlRecipe(rows: rows)),
    sourceUrl: url,
    importId: id,
  );
  return WebRecipeImportHandoff(
    result: result,
    originalUrl: url.toString(),
    finalUrl: url,
  );
}

class Fetch extends WebRecipeFetcher {
  String body = htmlRecipe();
  WebImportCancellation? token;
  String? input;
  @override
  Future<WebFetchedHtml> fetch(
    String input, {
    WebImportCancellation? cancellation,
  }) async {
    token = cancellation;
    this.input = input;
    return WebFetchedHtml(
      originalUrl: input,
      finalUrl: Uri.parse('https://unknown.example/r'),
      html: body,
      byteCount: body.length,
      redirectCount: 0,
    );
  }
}

class Repo implements RecipeRepository {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class Shopping implements ShoppingRepository {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  final input = find.byKey(const ValueKey('recipe-import-text'));
  final process = find.widgetWithText(FilledButton, 'Feldolgozás');
  Future<void> open(
    WidgetTester t,
    WebImportAction action, {
    ValueChanged<RecipeImportDraft?>? done,
    WebImportCancellation? lifetime,
    RecipeImportDraft Function(String)? parse,
  }) async {
    await t.pumpWidget(const SizedBox());
    await t.pump();
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('Open'),
              onPressed: () async {
                final result = await showDialog<RecipeImportDraft>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => RecipeImportDialog(
                    importWeb: action,
                    lifetime: lifetime,
                    parse: parse,
                  ),
                );
                done?.call(result);
              },
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Open'));
    await t.pumpAndSettle();
  }

  Future<void> submit(WidgetTester t, String text) async {
    await t.enterText(input, text);
    await t.pump();
    await t.ensureVisible(process);
    await t.tap(process);
    await t.pump();
  }

  test(
    'loader uses real extractor adapter and keeps final source, rejects FAIL',
    () async {
      final fetch = Fetch();
      final loader = WebRecipeImportLoader(fetcher: fetch);
      final token = WebImportCancellation();
      final r = await loader.load(
        ' https://original.example/r ',
        cancellation: token,
        importId: 'one',
      );
      expect(identical(fetch.token, token), true);
      expect(r.originalUrl, ' https://original.example/r ');
      expect(
        r.result.review!.issues.single.code,
        WebImportIssueCode.unverifiedSource,
      );
      fetch.body = '<html>none</html>';
      await expectLater(
        loader.load('https://a.example', cancellation: token, importId: 'two'),
        throwsA(isA<WebImportFailure>()),
      );
      fetch.body = htmlRecipe() + htmlRecipe();
      await expectLater(
        loader.load(
          'https://a.example',
          cancellation: token,
          importId: 'three',
        ),
        throwsA(
          isA<WebImportFailure>().having(
            (e) => e.code,
            'code',
            WebImportIssueCode.multipleRecipes,
          ),
        ),
      );
    },
  );
  testWidgets(
    'URL loading disables input/action, double tap once, PASS one handoff',
    (t) async {
      final future = Completer<WebRecipeImportHandoff>();
      int calls = 0, returns = 0;
      RecipeImportDraft? result;
      await open(
        t,
        (url, {required cancellation, required importId}) {
          calls++;
          expect(url, '  http://unknown.example/r  ');
          return future.future;
        },
        done: (r) {
          returns++;
          result = r;
        },
      );
      await submit(t, '  http://unknown.example/r  ');
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(t.widget<TextField>(input).enabled, false);
      expect(t.widget<FilledButton>(process).onPressed, isNull);
      await t.tap(process);
      await t.pump();
      expect(calls, 1);
      future.complete(handoff());
      await t.pumpAndSettle();
      expect(returns, 1);
      expect(result, isA<WebRecipeImportHandoff>());
      expect(find.byType(RecipeImportDialog), findsNothing);
    },
  );
  for (final host in ['unknown.example', 'nosalty.hu']) {
    testWidgets(
      '$host REVIEW notice and metadata survive explicit continuation',
      (t) async {
        RecipeImportDraft? result;
        final expected = handoff(host: host, rows: ['2 tbsp olaj']);
        await open(
          t,
          (u, {required cancellation, required importId}) async => expected,
          done: (r) => result = r,
        );
        await submit(t, 'https://$host/r');
        await t.pumpAndSettle();
        expect(result, isNull);
        expect(
          find.textContaining('Az automatikus import', findRichText: true),
          findsWidgets,
        );
        if (host == 'nosalty.hu') {
          expect(
            find.textContaining('különösen a mennyiségeket'),
            findsOneWidget,
          );
        }
        final next = find.widgetWithText(FilledButton, 'Tovább a szerkesztőbe');
        await t.ensureVisible(next);
        await t.tap(next);
        await t.pumpAndSettle();
        expect(identical(result, expected), true);
        expect(
          expected.result.review!.rows.single.issues.map((i) => i.code),
          contains(WebImportIssueCode.silentDbFallbackRisk),
        );
        expect(expected.result.review!.canSave, false);
      },
    );
  }
  for (final failure in [
    WebImportIssueCode.accessBlocked,
    WebImportIssueCode.rateLimited,
    WebImportIssueCode.timeout,
    WebImportIssueCode.noRecipe,
    WebImportIssueCode.invalidRecipe,
    WebImportIssueCode.multipleRecipes,
    WebImportIssueCode.tooLarge,
    WebImportIssueCode.invalidEncoding,
    WebImportIssueCode.fetchError,
  ]) {
    testWidgets('$failure retains URL and dialog, no handoff, retry succeeds', (
      t,
    ) async {
      int calls = 0, returns = 0;
      await open(t, (u, {required cancellation, required importId}) async {
        if (calls++ == 0) throw WebImportFailure(failure);
        return handoff();
      }, done: (_) => returns++);
      await submit(t, 'https://unknown.example/r');
      await t.pumpAndSettle();
      expect(find.byType(RecipeImportDialog), findsOneWidget);
      expect(
        t.widget<TextField>(input).controller!.text,
        'https://unknown.example/r',
      );
      expect(
        find.text(webImportErrorMessage(WebImportFailure(failure))),
        findsOneWidget,
      );
      expect(returns, 0);
      await t.ensureVisible(process);
      await t.tap(process);
      await t.pumpAndSettle();
      expect(returns, 1);
    });
  }
  testWidgets(
    'raw network exception hidden; failed URL can be replaced with text',
    (t) async {
      RecipeImportDraft? result;
      await open(
        t,
        (u, {required cancellation, required importId}) async =>
            throw StateError('SECRET raw stack'),
        done: (r) => result = r,
      );
      await submit(t, 'https://unknown.example');
      await t.pumpAndSettle();
      expect(find.textContaining('SECRET'), findsNothing);
      await submit(t, 'Alma\nHozzávalók:\n1 db alma\nElkészítés:\nFőzd.');
      await t.pumpAndSettle();
      expect(result!.title, 'Alma');
      expect(result, isNot(isA<WebRecipeImportHandoff>()));
    },
  );
  for (final useBack in [false, true]) {
    testWidgets(
      'cancel/back=$useBack cancels before confirmation, ignores late result',
      (t) async {
        final future = Completer<WebRecipeImportHandoff>();
        WebImportCancellation? token;
        int completed = 0;
        await open(
          t,
          (u, {required cancellation, required importId}) {
            token = cancellation;
            return future.future;
          },
          done: (r) {
            if (r != null) completed++;
          },
        );
        await submit(t, 'https://unknown.example');
        if (useBack) {
          await t.binding.handlePopRoute();
        } else {
          await t.tap(find.byTooltip('Bezárás'));
        }
        await t.pumpAndSettle();
        expect(token!.isCancelled, true);
        future.complete(handoff());
        await t.pumpAndSettle();
        expect(completed, 0);
        await t.tap(find.text('Kilépés'));
        await t.pumpAndSettle();
        expect(find.byType(RecipeImportDialog), findsNothing);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets('new operation ignores old completion and IDs differ', (t) async {
    final pending = [
      Completer<WebRecipeImportHandoff>(),
      Completer<WebRecipeImportHandoff>(),
    ];
    final ids = <String>[];
    int returns = 0;
    await open(
      t,
      (u, {required cancellation, required importId}) {
        ids.add(importId);
        return pending[ids.length - 1].future;
      },
      done: (r) {
        if (r != null) returns++;
      },
    );
    await submit(t, 'https://unknown.example/old');
    await t.tap(find.byTooltip('Bezárás'));
    await t.pumpAndSettle();
    await t.tap(find.text('Mégsem'));
    await t.pumpAndSettle();
    await submit(t, 'https://unknown.example/new');
    pending[0].complete(handoff());
    await t.pump();
    expect(returns, 0);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    pending[1].complete(handoff());
    await t.pumpAndSettle();
    expect(returns, 1);
    expect(ids.toSet().length, 2);
  });
  for (final dispose in [false, true]) {
    testWidgets('lifetime cancellation/dispose=$dispose ignores late result', (
      t,
    ) async {
      final lifetime = WebImportCancellation();
      final pending = Completer<WebRecipeImportHandoff>();
      WebImportCancellation? token;
      int returns = 0;
      await open(
        t,
        (u, {required cancellation, required importId}) {
          token = cancellation;
          return pending.future;
        },
        lifetime: lifetime,
        done: (r) {
          if (r != null) returns++;
        },
      );
      await submit(t, 'https://unknown.example');
      if (dispose) {
        await t.pumpWidget(const SizedBox());
      } else {
        lifetime.cancel();
      }
      await t.pumpAndSettle();
      expect(token!.isCancelled, true);
      pending.complete(handoff());
      await t.pumpAndSettle();
      expect(returns, 0);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
    'mixed/multiple/malformed inputs stay on old text parser branch',
    (t) async {
      for (final text in [
        'https://example.com ezt főzd',
        'https://a.example\nhttps://b.example',
        'https://',
      ]) {
        int calls = 0;
        await open(
          t,
          (u, {required cancellation, required importId}) async {
            calls++;
            return handoff();
          },
          parse: (s) {
            expect(s, text);
            throw StateError('test parser');
          },
        );
        await submit(t, text);
        await t.pumpAndSettle();
        expect(calls, 0);
      }
    },
  );
  testWidgets('MainScreen passes exact review envelope into unchanged editor', (
    t,
  ) async {
    final expected = handoff(host: 'nosalty.hu');
    await t.pumpWidget(
      MaterialApp(
        home: MainScreen(
          recipeRepository: Repo(),
          shoppingRepository: Shopping(),
          tabBodies: const [Text('R'), Text('S'), Text('W')],
          importWeb: (u, {required cancellation, required importId}) async =>
              expected,
        ),
      ),
    );
    await t.tap(find.byTooltip('Recept importálása'));
    await t.pumpAndSettle();
    await submit(t, 'https://nosalty.hu/r');
    await t.pumpAndSettle();
    final next = find.widgetWithText(FilledButton, 'Tovább a szerkesztőbe');
    await t.ensureVisible(next);
    await t.tap(next);
    await t.pumpAndSettle();
    final editor = t.widget<AddRecipeScreen>(find.byType(AddRecipeScreen));
    expect(identical(editor.webImport, expected), true);
    expect(identical(editor.initialImport, expected), true);
  });
  testWidgets(
    'MainScreen account subtree replacement cancels surviving dialog route',
    (t) async {
      final account = ValueNotifier('A');
      addTearDown(account.dispose);
      final pending = Completer<WebRecipeImportHandoff>();
      WebImportCancellation? token;
      await t.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<String>(
            valueListenable: account,
            builder: (_, uid, _) => MainScreen(
              key: ValueKey(uid),
              recipeRepository: Repo(),
              shoppingRepository: Shopping(),
              tabBodies: [Text(uid), const Text('S'), const Text('W')],
              importWeb: (u, {required cancellation, required importId}) {
                token = cancellation;
                return pending.future;
              },
            ),
          ),
        ),
      );
      await t.tap(find.byTooltip('Recept importálása'));
      await t.pumpAndSettle();
      await submit(t, 'https://unknown.example');
      account.value = 'B';
      await t.pumpAndSettle();
      expect(token!.isCancelled, true);
      expect(find.byType(RecipeImportDialog), findsNothing);
      pending.complete(handoff());
      await t.pumpAndSettle();
      expect(find.byType(AddRecipeScreen), findsNothing);
      expect(find.text('B'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'account invalidation during discard confirmation removes only owned routes',
    (t) async {
      final lifetime = WebImportCancellation();
      await open(
        t,
        (u, {required cancellation, required importId}) async => handoff(),
        lifetime: lifetime,
      );
      await t.enterText(input, 'https://unknown.example');
      await t.tap(find.byTooltip('Bezárás'));
      await t.pumpAndSettle();
      lifetime.cancel();
      await t.pumpAndSettle();
      expect(find.byType(RecipeImportDialog), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Open'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'web error remains scrollable on small screen with keyboard and large text',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(360, 740);
      t.view.viewInsets = const FakeViewPadding(bottom: 300);
      t.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetViewInsets);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await open(
        t,
        (u, {required cancellation, required importId}) async =>
            throw const WebImportFailure(WebImportIssueCode.accessBlocked),
      );
      await submit(t, 'https://unknown.example');
      await t.pumpAndSettle();
      await t.ensureVisible(process);
      await t.pumpAndSettle();
      expect(process.hitTestable(), findsOneWidget);
      expect(
        t.widget<TextField>(input).controller!.text,
        'https://unknown.example',
      );
      expect(t.takeException(), isNull);
    },
  );
}
