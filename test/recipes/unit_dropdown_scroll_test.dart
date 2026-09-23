import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/core/domain/measurement_units.dart';
import 'package:kuktam/recipes/presentation/widgets/ingredient_row.dart';
import 'package:kuktam/shopping/data/repositories/shopping_repository.dart';
import 'package:kuktam/shopping/domain/shopping_units.dart';
import 'package:kuktam/shopping/presentation/widgets/shopping_import_dialog.dart';
import 'package:kuktam/shopping/presentation/widgets/shopping_item_dialog.dart';

class _UnusedRepository implements ShoppingRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final surface in ['recipe', 'shopping item', 'shopping import']) {
    for (final config in [(320.0, 1.0), (400.0, 1.6)]) {
      testWidgets('$surface popup scroll and all units at $config', (
        tester,
      ) async {
        tester.view.physicalSize = Size(config.$1, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final data = IngredientRowData(name: 'Liszt', quantity: '1');
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(config.$2)),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  if (surface == 'recipe') {
                    return Padding(
                      padding: const EdgeInsets.all(20),
                      child: IngredientRow(
                        data: data,
                        units: MeasurementUnits.values,
                        suggestions: const [],
                        onRemove: () {},
                      ),
                    );
                  }
                  return TextButton(
                    onPressed: () {
                      if (surface == 'shopping item') {
                        showShoppingItemDialog(
                          context: context,
                          shoppingRepository: _UnusedRepository(),
                        );
                      } else {
                        showDialog<void>(
                          context: context,
                          builder: (_) =>
                              ShoppingImportDialog(addItems: (_) async {}),
                        );
                      }
                    },
                    child: const Text('Open'),
                  );
                },
              ),
            ),
          ),
        );
        if (surface != 'recipe') {
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
        }
        if (surface == 'shopping import') {
          await tester.enterText(
            find.byKey(const ValueKey('import-text')),
            '1 g liszt',
          );
          await tester.pump();
          await tester.ensureVisible(find.text('Feldolgozás'));
          await tester.tap(find.text('Feldolgozás'));
          await tester.pumpAndSettle();
        }
        final selector = find.byType(DropdownButtonFormField<String>);
        await tester.ensureVisible(selector);
        final dropdown = tester.widget<DropdownButton<String>>(
          find.descendant(
            of: selector,
            matching: find.byType(DropdownButton<String>),
          ),
        );
        final units = surface == 'recipe'
            ? MeasurementUnits.values
            : shoppingUnits;
        expect(dropdown.items!.map((item) => item.value), orderedEquals(units));
        // The cap includes a fractional row, accounting for Material top padding.
        final rowHeight = dropdown.itemHeight ?? kMinInteractiveDimension;
        final fraction =
            ((dropdown.menuMaxHeight! - 8) % rowHeight) / rowHeight;
        expect(fraction, inInclusiveRange(0.3, 0.5));

        for (final unit in units) {
          await tester.tap(selector);
          await tester.pumpAndSettle();
          final menu = find.byType(ListView).last;
          final scroll = find
              .descendant(of: menu, matching: find.byType(Scrollable))
              .first;
          final position = tester.state<ScrollableState>(scroll).position;
          expect(position.maxScrollExtent, greaterThan(0));
          expect(position.viewportDimension % rowHeight, greaterThan(0));
          // Start from the top, then reach even the last unit through the real menu.
          position.jumpTo(0);
          await tester.pumpAndSettle();
          final item = find.descendant(of: menu, matching: find.text(unit));
          await tester.scrollUntilVisible(item, 80, scrollable: scroll);
          await tester.pumpAndSettle();
          expect(item.hitTestable(), findsOneWidget);
          await tester.tap(item);
          await tester.pumpAndSettle();
          expect(tester.state<FormFieldState<String>>(selector).value, unit);
          if (surface == 'recipe') expect(data.selectedUnit, unit);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
        data.dispose();
      });
    }
  }
}
