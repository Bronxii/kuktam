import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/shopping/data/repositories/shopping_repository.dart';
import 'package:kuktam/shopping/presentation/widgets/shopping_item_dialog.dart';
import 'package:kuktam/shopping/domain/models/shopping_item.dart';
import 'package:kuktam/shopping/domain/shopping_quantity_formatter.dart';
import 'package:kuktam/shopping/presentation/screens/shopping_screen.dart';
import 'package:kuktam/shopping/presentation/widgets/shopping_item_tile.dart';
import 'package:kuktam/home/presentation/screens/main_screen.dart';
import 'package:flutter/services.dart';
import 'package:kuktam/features/auth/data/repositories/auth_repository.dart';
import 'package:kuktam/features/auth/presentation/widgets/auth_gate.dart';
import '../recipes/recipe_repository_test.dart'
    show RecipeTestAuth, RecipeTestUser;

class ShoppingFake implements ShoppingRepository {
  final events = StreamController<List<ShoppingItem>>.broadcast();
  List<ShoppingItem> items = [];
  bool loadFail = false, waitLoad = false;
  int loads = 0;
  @override
  Stream<List<ShoppingItem>> watchShoppingItems() async* {
    loads++;
    if (loadFail) throw StateError('private backend error');
    if (!waitLoad) yield List.of(items);
    yield* events.stream;
  }

  Future<void> _write() async {
    writes++;
    if (pending != null) await pending!.future;
    if (fail) throw StateError('private backend error');
  }

  @override
  Future<void> updateItem({
    required String id,
    required String name,
    required double quantity,
    required String unit,
  }) async {
    added.add((name: name, quantity: quantity, unit: unit));
    await _write();
  }

  @override
  Future<void> deleteItem(String id) async {
    await _write();
    items.removeWhere((i) => i.id == id);
    events.add(List.of(items));
  }

  @override
  Future<void> setItemChecked({
    required String id,
    required bool isChecked,
  }) async {
    await _write();
    items = [
      for (final i in items)
        ShoppingItem(
          id: i.id,
          name: i.name,
          quantity: i.quantity,
          unit: i.unit,
          isChecked: i.id == id ? isChecked : i.isChecked,
        ),
    ];
    events.add(List.of(items));
  }

  @override
  Future<void> clearShoppingList() async {
    await _write();
    items.clear();
    events.add([]);
  }

  int writes = 0;
  Completer<void>? pending;
  bool fail = false;
  List<ShoppingItemInput> added = [];
  @override
  Future<void> addOrMergeItem({
    required String name,
    required double quantity,
    required String unit,
  }) async {
    writes++;
    added.add((name: name, quantity: quantity, unit: unit));
    if (pending != null) await pending!.future;
    if (fail) throw StateError('private error');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> openItem(WidgetTester tester, ShoppingFake repo) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showShoppingItemDialog(
              context: context,
              shoppingRepository: repo,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).first, 'Tej');
}

void main() {
  testWidgets('rapid delete confirmation cannot pop the shopping screen', (
    tester,
  ) async {
    final repo = ShoppingFake()
      ..items = [
        const ShoppingItem(
          id: 'one',
          name: 'Alma',
          quantity: 1,
          unit: 'db',
          isChecked: false,
        ),
      ]
      ..pending = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    body: ShoppingListScreen(shoppingRepository: repo),
                  ),
                ),
              ),
              child: const Text('Open list'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open list'));
    await tester.pumpAndSettle();
    tester
        .widget<ShoppingItemTile>(find.byType(ShoppingItemTile))
        .onItemLongPress();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Törlés'));
    await tester.pumpAndSettle();
    final confirm = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Törlés'))
        .onPressed!;
    confirm();
    confirm();
    await tester.pump();
    expect(find.byType(ShoppingListScreen), findsOneWidget);
    expect(repo.writes, 1);
    repo.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(ShoppingListScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await repo.events.close();
  });
  const milk = ShoppingItem(
    id: 'milk',
    name: 'Tej',
    quantity: 1500,
    unit: 'ml',
    isChecked: false,
  );
  for (final example in <(double, String, String)>[
    (999.6, 'g', '1000 g'),
    (1500, 'ml', '1,5 l'),
    (.001, 'db', '0,5 db'),
    (1.236, 'l', '1,24 l'),
    (.125, 'kg', '125 g'),
  ]) {
    test('shared shopping display ${example.$1} ${example.$2}', () {
      expect(formatShoppingAmount(example.$1, example.$2), example.$3);
    });
  }
  testWidgets(
    'loading error retry empty and stream refresh without duplicate subscriptions',
    (tester) async {
      final repo = ShoppingFake()..waitLoad = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ShoppingListScreen(shoppingRepository: repo)),
        ),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      repo.events.addError(StateError('private backend error'));
      await tester.pumpAndSettle();
      expect(find.textContaining('private backend'), findsNothing);
      expect(find.text('Újra'), findsOneWidget);
      repo.waitLoad = false;
      await tester.tap(find.text('Újra'));
      await tester.pumpAndSettle();
      expect(find.text('A bevásárlólistád üres!'), findsOneWidget);
      repo.events.add([milk]);
      await tester.pumpAndSettle();
      expect(find.byType(ShoppingItemTile), findsOneWidget);
      expect(repo.loads, 2);
      await tester.pumpWidget(const SizedBox());
      await repo.events.close();
    },
  );
  testWidgets(
    'check failure retry and duplicate callbacks use one pending write',
    (tester) async {
      final repo = ShoppingFake()
        ..items = [milk]
        ..fail = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ShoppingListScreen(shoppingRepository: repo)),
        ),
      );
      await tester.pumpAndSettle();
      tester
          .widget<ShoppingItemTile>(find.byType(ShoppingItemTile))
          .onCheckedChanged();
      await tester.pumpAndSettle();
      expect(find.textContaining('Nem sikerült módosítani'), findsOneWidget);
      expect(repo.items.single.isChecked, isFalse);
      repo.fail = false;
      repo.pending = Completer<void>();
      final toggle = tester
          .widget<ShoppingItemTile>(find.byType(ShoppingItemTile))
          .onCheckedChanged;
      toggle();
      toggle();
      await tester.pump();
      expect(repo.writes, 2);
      repo.pending!.complete();
      await tester.pumpAndSettle();
      expect(repo.items.single.isChecked, isTrue);
      expect(repo.loads, 1);
      await tester.pumpWidget(const SizedBox());
      await repo.events.close();
    },
  );
  for (final operation in ['delete', 'clear']) {
    testWidgets('$operation cancel error retry and refresh', (tester) async {
      final repo = ShoppingFake()
        ..items = [milk]
        ..fail = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ShoppingListScreen(shoppingRepository: repo)),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> confirm() async {
        if (operation == 'delete') {
          tester
              .widget<ShoppingItemTile>(find.byType(ShoppingItemTile))
              .onItemLongPress();
          await tester.pumpAndSettle();
          await tester.tap(find.text('Törlés'));
        } else {
          await tester.tap(find.text('Bevásárlás befejezése'));
        }
        await tester.pumpAndSettle();
      }

      await confirm();
      await tester.tap(find.text(operation == 'delete' ? 'Mégse' : 'Mégsem'));
      await tester.pumpAndSettle();
      expect(repo.writes, 0);
      await confirm();
      await tester.tap(
        find.widgetWithText(
          FilledButton,
          operation == 'delete' ? 'Törlés' : 'Befejezés',
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.items, hasLength(1));
      expect(find.textContaining('Nem sikerült módosítani'), findsOneWidget);
      repo.fail = false;
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await confirm();
      await tester.tap(
        find.widgetWithText(
          FilledButton,
          operation == 'delete' ? 'Törlés' : 'Befejezés',
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.items, isEmpty);
      expect(find.text('A bevásárlólistád üres!'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await repo.events.close();
    });
  }
  testWidgets(
    'manual create validation failure preserves input and retry uses decimal comma',
    (tester) async {
      final repo = ShoppingFake()..fail = true;
      await openItem(tester, repo);
      await tester.enterText(find.byType(TextField).first, '   ');
      await tester.tap(find.text('Hozzáadás'));
      await tester.pumpAndSettle();
      expect(repo.writes, 0);
      await tester.enterText(find.byType(TextField).first, 'Tej');
      await tester.enterText(find.byType(TextField).last, '1,5');
      await tester.tap(find.text('Hozzáadás'));
      await tester.pumpAndSettle();
      expect(find.text('Nem sikerült menteni a tételt.'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        '1,5',
      );
      repo.fail = false;
      await tester.tap(find.text('Hozzáadás'));
      await tester.pumpAndSettle();
      expect(repo.added.last.quantity, 1.5);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
  testWidgets('edit retains checked item values cancel and failed retry', (
    tester,
  ) async {
    final repo = ShoppingFake()
      ..items = [milk]
      ..fail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ShoppingListScreen(shoppingRepository: repo)),
      ),
    );
    await tester.pumpAndSettle();
    tester
        .widget<ShoppingItemTile>(find.byType(ShoppingItemTile))
        .onItemLongPress();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Szerkesztés'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller!.text,
      '1500',
    );
    await tester.enterText(find.byType(TextField).first, 'Másik tej');
    await tester.tap(find.text('Mentés'));
    await tester.pumpAndSettle();
    expect(find.text('Nem sikerült menteni a tételt.'), findsOneWidget);
    repo.fail = false;
    await tester.tap(find.text('Mentés'));
    await tester.pumpAndSettle();
    expect(repo.added.last.name, 'Másik tej');
    expect(repo.writes, 2);
    await tester.pumpWidget(const SizedBox());
    await repo.events.close();
  });
  testWidgets(
    'AuthGate A B A cancels stale shopping stream during pending load',
    (tester) async {
      final auth = RecipeTestAuth();
      final a = ShoppingFake()..waitLoad = true;
      final b = ShoppingFake()
        ..items = [
          const ShoppingItem(
            id: 'b',
            name: 'B saját',
            quantity: 1,
            unit: 'db',
            isChecked: false,
          ),
        ];
      await tester.pumpWidget(
        MaterialApp(
          home: AuthGate(
            authRepository: AuthRepository(firebaseAuth: auth),
            mainBuilder: (_) => Scaffold(
              body: ShoppingListScreen(
                shoppingRepository: auth.currentUser!.uid == 'A' ? a : b,
              ),
            ),
          ),
        ),
      );
      auth.changes.add(auth.currentUser);
      await tester.pump();
      await tester.pump();
      auth.currentUser = RecipeTestUser('B');
      auth.changes.add(auth.currentUser);
      await tester.pumpAndSettle();
      a.events.add([milk]);
      await tester.pumpAndSettle();
      expect(find.text('Tej'), findsNothing);
      expect(find.text('B saját'), findsOneWidget);
      a.waitLoad = false;
      a.items = [milk];
      auth.currentUser = RecipeTestUser('A');
      auth.changes.add(auth.currentUser);
      await tester.pumpAndSettle();
      expect(find.text('Tej'), findsOneWidget);
      expect(find.text('B saját'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await a.events.close();
      await b.events.close();
      await auth.changes.close();
    },
  );
  testWidgets(
    'share uses all checked states stable order Unicode and shared formatting; errors retry',
    (tester) async {
      final repo = ShoppingFake()
        ..items = [
          milk,
          const ShoppingItem(
            id: 'a',
            name: 'Áfonya',
            quantity: 999.6,
            unit: 'g',
            isChecked: true,
          ),
        ];
      final calls = <MethodCall>[];
      const channel = MethodChannel('dev.fluttercommunity.plus/share');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return 'success';
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MainScreen(
            shoppingRepository: repo,
            tabBodies: const [SizedBox(), SizedBox(), SizedBox()],
          ),
        ),
      );
      await tester.tap(find.text('Lista'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Bevásárlólista megosztása'));
      await tester.pumpAndSettle();
      expect(calls, hasLength(1));
      final text = (calls.single.arguments as Map)['text'] as String;
      expect(text, contains('• Tej – 1,5 l\n• Áfonya – 1000 g'));
      repo.loadFail = true;
      await tester.tap(find.byTooltip('Bevásárlólista megosztása'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Nem sikerült megosztani'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      repo.loadFail = false;
      repo.items = [];
      await tester.tap(find.byTooltip('Bevásárlólista megosztása'));
      await tester.pumpAndSettle();
      expect(calls, hasLength(1));
      expect(find.text('A bevásárlólista üres.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await repo.events.close();
    },
  );
  testWidgets(
    'manual input rejects nonfinite quantities before repository write',
    (tester) async {
      final repo = ShoppingFake();
      await openItem(tester, repo);
      for (final value in ['NaN', 'Infinity', '0', '-1', 'abc', '1..2', ' ']) {
        await tester.enterText(find.byType(TextField).last, value);
        await tester.tap(find.text('Hozzáadás'));
        await tester.pumpAndSettle();
        expect(repo.writes, 0, reason: value);
        expect(find.text('Adj meg érvényes mennyiséget.'), findsOneWidget);
      }
    },
  );
  testWidgets(
    'rapid save invokes repository once and protects pending dialog',
    (tester) async {
      final repo = ShoppingFake()..pending = Completer<void>();
      await openItem(tester, repo);
      final save = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Hozzáadás'))
          .onPressed!;
      save();
      save();
      await tester.pump();
      expect(repo.writes, 1);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);
      repo.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
}
