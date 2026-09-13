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
    expect(tester.widget<TextField>(quantity(1)).controller!.text, '125');
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
