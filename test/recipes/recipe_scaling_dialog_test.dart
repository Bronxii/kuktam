import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/recipes/domain/models/recipe.dart';
import 'package:kuktam/recipes/presentation/screens/recipe_details_screen.dart';
import 'package:kuktam/recipes/presentation/widgets/recipe_scaling_dialog.dart';

void main() {
  const ingredients = [
    RecipeIngredient(name: 'Liszt', quantity: 1250, unit: 'g'),
    RecipeIngredient(name: 'Vaj', quantity: 0.125, unit: 'kg'),
    RecipeIngredient(name: 'Tej', quantity: 1250, unit: 'ml'),
    RecipeIngredient(name: 'Víz', quantity: 0.125, unit: 'l'),
  ];
  const recipe = Recipe(
    name: 'Próbarecept',
    ingredients: ingredients,
    spices: [RecipeSpice(name: 'Fűszer csak a receptben')],
    preparation: 'Elkészítés csak a receptben',
  );

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: RecipeDetailsScreen(recipe: recipe)),
    );
    await tester.tap(find.text('Átszámítás'));
    await tester.pumpAndSettle();
  }

  Finder quantity(int index) => find.byKey(ValueKey('scaling-quantity-$index'));

  testWidgets(
    'details entry opens normalized ingredients only without autofocus',
    (tester) async {
      await openDialog(tester);
      final dialog = find.byType(RecipeScalingDialog);
      expect(
        find.descendant(of: dialog, matching: find.text(recipe.preparation)),
        findsNothing,
      );
      expect(
        find.descendant(
          of: dialog,
          matching: find.text(recipe.spices.single.name),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: dialog, matching: find.byType(TextField)),
        findsNWidgets(4),
      );
      for (var i = 0; i < ingredients.length; i++) {
        final field = tester.widget<TextField>(quantity(i));
        expect(field.controller!.text, i.isEven ? '1,25' : '125');
        expect(field.focusNode!.hasFocus, isFalse);
        expect(
          find.descendant(
            of: find.byKey(ValueKey('scaling-row-$i')),
            matching: find.text(ingredients[i].name),
          ),
          findsOneWidget,
        );
      }
      for (final unit in ['kg', 'g', 'l', 'ml']) {
        expect(
          find.descendant(of: dialog, matching: find.text(unit)),
          findsOneWidget,
        );
      }
      expect(tester.testTextInput.isVisible, isFalse);
      final shopping = find.widgetWithText(
        FilledButton,
        'Bevásárlólistához adás',
      );
      expect(tester.widget<FilledButton>(shopping).onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('editing is local and reset restores original display values', (
    tester,
  ) async {
    await openDialog(tester);
    final firstController = tester.widget<TextField>(quantity(0)).controller;
    final firstFocus = tester.widget<TextField>(quantity(0)).focusNode;
    await tester.enterText(quantity(0), '2,5');
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<TextField>(quantity(1)).controller!.text, '0,25');
    expect(ingredients[0].quantity, 1250);
    await tester.ensureVisible(find.text('Visszaállítás'));
    await tester.tap(find.text('Visszaállítás'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(quantity(0)).controller!.text, '1,25');
    expect(
      tester.widget<TextField>(quantity(0)).controller,
      same(firstController),
    );
    expect(tester.widget<TextField>(quantity(0)).focusNode, same(firstFocus));
    expect(find.text('kg'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('barrier does not dismiss; X asks and cancel preserves draft', (
    tester,
  ) async {
    await openDialog(tester);
    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();
    expect(find.byType(RecipeScalingDialog), findsOneWidget);
    await tester.enterText(quantity(0), '1,5');
    await tester.ensureVisible(find.byTooltip('Bezárás'));
    await tester.tap(find.byTooltip('Bezárás'));
    await tester.pumpAndSettle();
    expect(find.text('Kilépsz az átszámításból?'), findsOneWidget);
    await tester.tap(find.text('Mégsem'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(quantity(0)).controller!.text, '1,5');
    await tester.tap(find.byTooltip('Bezárás'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kilépés'));
    await tester.pumpAndSettle();
    expect(find.byType(RecipeScalingDialog), findsNothing);
    expect(find.byType(RecipeDetailsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Android back asks for confirmation and closes only dialog', (
    tester,
  ) async {
    await openDialog(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Kilépsz az átszámításból?'), findsOneWidget);
    await tester.tap(find.text('Kilépés'));
    await tester.pumpAndSettle();
    expect(find.byType(RecipeDetailsScreen), findsOneWidget);
    expect(find.byType(RecipeScalingDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  const basic = [
    RecipeIngredient(name: 'Vaj', quantity: 200, unit: 'g'),
    RecipeIngredient(name: 'Liszt', quantity: 500, unit: 'g'),
    RecipeIngredient(name: 'Tej', quantity: 300, unit: 'ml'),
    RecipeIngredient(name: 'Tojás', quantity: 2, unit: 'db'),
  ];

  Future<void> openBasic(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RecipeScalingDialog(ingredients: basic)),
      ),
    );
    await tester.pumpAndSettle();
  }

  List<String> values(WidgetTester tester) => [
    for (var i = 0; i < 4; i++)
      tester.widget<TextField>(quantity(i)).controller!.text,
  ];

  testWidgets('debounce waits exactly 500 ms and uses original snapshot', (
    tester,
  ) async {
    await openBasic(tester);
    await tester.enterText(quantity(0), '250');
    await tester.pump(const Duration(milliseconds: 499));
    expect(values(tester), ['250', '500', '300', '2']);
    await tester.pump(const Duration(milliseconds: 1));
    expect(values(tester), ['250', '625', '375', '2,5']);
    await tester.enterText(quantity(2), '450');
    await tester.pump(const Duration(milliseconds: 500));
    expect(values(tester), ['300', '750', '450', '3']);
    expect(basic.map((i) => i.quantity), [200, 500, 300, 2]);
  });

  testWidgets('fast input restarts the single debounce', (tester) async {
    await openBasic(tester);
    for (final text in ['2', '25']) {
      await tester.enterText(quantity(0), text);
      await tester.pump(const Duration(milliseconds: 300));
      expect(values(tester).skip(1), ['500', '300', '2']);
    }
    await tester.enterText(quantity(0), '250');
    await tester.pump(const Duration(milliseconds: 499));
    expect(values(tester).skip(1), ['500', '300', '2']);
    await tester.pump(const Duration(milliseconds: 1));
    expect(values(tester), ['250', '625', '375', '2,5']);
  });

  testWidgets('Done flushes immediately and subsequent blur does not rescale', (
    tester,
  ) async {
    await openDialog(tester);
    await tester.enterText(quantity(0), '0,125'); // kg, normalizes to 125 g
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(values(tester), ['125', '13', '125', '13']);
    tester.widget<TextField>(quantity(0)).focusNode!.unfocus();
    await tester.pump(const Duration(seconds: 1));
    expect(values(tester), ['125', '13', '125', '13']);
  });

  testWidgets('focus loss flushes pending input immediately', (tester) async {
    await openBasic(tester);
    await tester.enterText(quantity(0), '250');
    tester.widget<TextField>(quantity(1)).focusNode!.requestFocus();
    await tester.pump();
    expect(values(tester), ['250', '625', '375', '2,5']);
  });

  for (final input in ['1,5', '1.5', '2,5']) {
    testWidgets('decimal input $input preserves fractional pieces', (
      tester,
    ) async {
      await openBasic(tester);
      await tester.enterText(quantity(3), input);
      await tester.pump(const Duration(milliseconds: 500));
      final factor = double.parse(input.replaceAll(',', '.')) / 2;
      expect(values(tester)[0], '${(200 * factor).toInt()}');
      expect(values(tester)[3], input);
    });
  }

  testWidgets('display kg to original g and display g to original kg', (
    tester,
  ) async {
    await openDialog(tester);
    await tester.enterText(quantity(0), '1,5');
    await tester.pump(const Duration(milliseconds: 500));
    expect(values(tester), ['1,5', '0,15', '1,5', '0,15']);
    await tester.ensureVisible(find.text('Visszaállítás'));
    await tester.tap(find.text('Visszaállítás'));
    await tester.pumpAndSettle();
    await tester.enterText(quantity(1), '150');
    await tester.pump(const Duration(milliseconds: 500));
    expect(values(tester), ['1,5', '150', '1,5', '0,15']);
  });

  testWidgets(
    'active raw text selection and unit survive debounce; blur normalizes',
    (tester) async {
      await openDialog(tester);
      await tester.enterText(quantity(0), '0,1250');
      final field = tester.widget<TextField>(quantity(0));
      field.controller!.selection = const TextSelection.collapsed(offset: 3);
      await tester.pump(const Duration(milliseconds: 500));
      expect(field.controller!.text, '0,1250');
      expect(field.controller!.selection.baseOffset, 3);
      expect(field.focusNode!.hasFocus, isTrue);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('scaling-row-0')),
          matching: find.text('kg'),
        ),
        findsOneWidget,
      );
      field.focusNode!.unfocus();
      await tester.pump();
      expect(field.controller!.text, '125');
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('scaling-row-0')),
          matching: find.text('g'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('1,50 remains raw until Done, without controller cascades', (
    tester,
  ) async {
    await openBasic(tester);
    var writes = 0;
    final other = tester.widget<TextField>(quantity(0)).controller!;
    other.addListener(() => writes++);
    await tester.enterText(quantity(3), '1,50');
    await tester.pump(const Duration(milliseconds: 500));
    expect(values(tester)[3], '1,50');
    expect(writes, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(writes, 1);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(values(tester)[3], '1,5');
    expect(writes, 1);
  });

  for (final input in ['', ',', '.', '0', '-1', 'abc', '1,2.3']) {
    testWidgets(
      'invalid draft "$input" preserves last success; another row recovers',
      (tester) async {
        await openBasic(tester);
        await tester.enterText(quantity(0), '250');
        await tester.pump(const Duration(milliseconds: 500));
        await tester.enterText(quantity(0), input);
        await tester.pump(const Duration(milliseconds: 500));
        expect(values(tester), [input, '625', '375', '2,5']);
        expect(
          tester.widget<TextField>(quantity(0)).decoration!.errorText,
          isNotNull,
        );
        await tester.enterText(quantity(1), '750');
        await tester.pump(const Duration(milliseconds: 500));
        expect(values(tester), ['300', '750', '450', '3']);
        expect(
          tester.widget<TextField>(quantity(0)).decoration!.errorText,
          isNull,
        );
      },
    );
  }

  testWidgets('reset cancels pending input and clears validation permanently', (
    tester,
  ) async {
    await openBasic(tester);
    await tester.enterText(quantity(0), '');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(quantity(1), '750');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.ensureVisible(find.text('Visszaállítás'));
    await tester.tap(find.text('Visszaállítás'));
    await tester.pump(const Duration(seconds: 1));
    expect(values(tester), ['200', '500', '300', '2']);
    expect(tester.widget<TextField>(quantity(0)).decoration!.errorText, isNull);
  });

  testWidgets('disposing with pending debounce leaves no callback', (
    tester,
  ) async {
    await openBasic(tester);
    await tester.enterText(quantity(0), '250');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('duplicate ingredient names still use row index', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RecipeScalingDialog(
            ingredients: [
              RecipeIngredient(name: 'Liszt', quantity: 200, unit: 'g'),
              RecipeIngredient(name: 'Liszt', quantity: 500, unit: 'g'),
            ],
          ),
        ),
      ),
    );
    await tester.enterText(quantity(1), '750');
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.widget<TextField>(quantity(0)).controller!.text, '300');
  });

  testWidgets('rounded display never becomes the basis of later scaling', (
    tester,
  ) async {
    await openBasic(tester);
    await tester.enterText(quantity(0), '235,294117647059');
    await tester.pump(const Duration(milliseconds: 500));
    expect(values(tester), ['235,294117647059', '588', '353', '2,5']);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(values(tester)[0], '235');
    await tester.enterText(quantity(2), '450');
    await tester.pump(const Duration(milliseconds: 500));
    expect(values(tester), ['300', '750', '450', '3']);
    await tester.enterText(quantity(0), '850');
    await tester.pump(const Duration(milliseconds: 500));
    expect(values(tester)[1], '2,13');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('scaling-row-1')),
        matching: find.text('kg'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('small viewport, keyboard and long list stay scrollable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final many = List.generate(
      30,
      (i) => RecipeIngredient(
        name:
            'Nagyon hosszú hozzávalónév több szóval és részletes megnevezéssel $i',
        quantity: 2.5,
        unit: 'konzerv',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => RecipeScalingDialog(ingredients: many),
              ),
              child: const Text('Nyitás'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Nyitás'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    await tester.ensureVisible(quantity(29));
    await tester.enterText(quantity(29), '3');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Visszaállítás'));
    await tester.tap(find.text('Visszaállítás'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(quantity(29)).controller!.text, '2,5');
    expect(tester.takeException(), isNull);
  });
}
