import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/core/domain/measurement_units.dart';
import 'package:kuktam/recipes/presentation/widgets/ingredient_row.dart';

void main() {
  for (final width in [320.0, 360.0, 400.0]) {
    for (final unit in ['g', 'ml', 'dl', 'db', 'kg', 'l', 'tk', 'ek']) {
      testWidgets('ingredient row $width: full quantity label and $unit', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final data = IngredientRowData(unit: unit);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(20),
                child: IngredientRow(
                  data: data,
                  units: [...MeasurementUnits.values, 'dl'],
                  suggestions: const [],
                  onRemove: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Mennyiség'), findsOneWidget);
        expect(
          tester
              .renderObject<RenderParagraph>(find.text('Mennyiség'))
              .didExceedMaxLines,
          isFalse,
        );
        final selected = find.text(unit).first;
        final paragraph = tester.renderObject<RenderParagraph>(selected);
        expect(paragraph.didExceedMaxLines, isFalse);
        final painter = TextPainter(
          text: paragraph.text,
          textDirection: paragraph.textDirection,
          textScaler: paragraph.textScaler,
        )..layout();
        expect(paragraph.size.width, greaterThanOrEqualTo(painter.width - 0.1));
        painter.dispose();
        final name = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == 'Hozzávaló',
        );
        const longName =
            'Nagyon hosszú hozzávalónév extra szűz hidegen sajtolt olívaolaj';
        await tester.enterText(name, longName);
        await tester.pumpAndSettle();
        expect(data.nameController.text, longName);
        expect(tester.widget<TextField>(name).maxLines, 1);
        final editable = tester.state<EditableTextState>(
          find.descendant(of: name, matching: find.byType(EditableText)),
        );
        expect(editable.renderEditable.offset.pixels, greaterThan(0));
        expect(data.selectedUnit, unit);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        data.dispose();
      });
    }
  }
}
