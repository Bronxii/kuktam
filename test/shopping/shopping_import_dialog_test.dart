import 'dart:async';
import 'package:flutter/material.dart';
import 'package:kuktam/shopping/data/repositories/shopping_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/shopping/presentation/widgets/shopping_import_dialog.dart';
import 'package:kuktam/shopping/domain/shopping_units.dart';

void main() {
  final input = find.byKey(const ValueKey('import-text'));
  Future<void> open(
    WidgetTester tester, {
    Future<void> Function(List<ShoppingItemInput>)? addItems,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => addItems == null
                  ? showShoppingImportDialog(context)
                  : showDialog<void>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => ShoppingImportDialog(addItems: addItems),
                    ),
              child: const Text('Importálás'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Importálás'));
    await tester.pumpAndSettle();
  }

  Future<void> preview(WidgetTester tester, String text) async {
    await tester.enterText(input, text);
    await tester.pump();
    await tester.ensureVisible(find.text('Feldolgozás'));
    await tester.tap(find.text('Feldolgozás'));
    await tester.pumpAndSettle();
  }

  List<TextField> fields(WidgetTester tester) =>
      tester.widgetList<TextField>(find.byType(TextField)).toList();

  final save = find.widgetWithText(
    FilledButton,
    'Hozzáadás a bevásárlólistához',
  );
  bool canSave(WidgetTester tester) =>
      tester.widget<FilledButton>(save).onPressed != null;

  testWidgets(
    'final validation rejects invalid fields and accepts localized precision',
    (tester) async {
      await open(tester);
      await preview(tester, 'alma');
      expect(canSave(tester), isTrue);
      await tester.enterText(find.byType(TextField).first, '  ');
      await tester.pump();
      expect(canSave(tester), isFalse);
      await tester.enterText(find.byType(TextField).first, 'alma');
      for (final invalid in ['', '0', '-1', 'NaN', 'Infinity', '1,2.3']) {
        await tester.enterText(find.byType(TextField).last, invalid);
        await tester.pump();
        expect(canSave(tester), isFalse, reason: invalid);
      }
      await tester.enterText(find.byType(TextField).last, '1,234');
      await tester.pump();
      expect(canSave(tester), isTrue);
    },
  );

  testWidgets(
    'middle deletion preserves remaining controllers; empty list cannot save',
    (tester) async {
      await open(tester);
      await preview(tester, 'alma;tej;kenyér');
      final first = fields(tester)[0].controller;
      final last = fields(tester)[4].controller;
      await tester.enterText(find.byType(TextField).at(4), 'barna kenyér');
      await tester.tap(find.byTooltip('Tétel törlése').at(1));
      await tester.pumpAndSettle();
      expect(fields(tester).map((f) => f.controller!.text), [
        'alma',
        '1',
        'barna kenyér',
        '1',
      ]);
      expect(fields(tester)[0].controller, same(first));
      expect(fields(tester)[2].controller, same(last));
      await tester.tap(find.byTooltip('Tétel törlése').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Tétel törlése'));
      await tester.pumpAndSettle();
      expect(fields(tester), isEmpty);
      expect(canSave(tester), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'manual row defaults invalid then becomes valid without changing existing row',
    (tester) async {
      await open(tester);
      await preview(tester, 'alma');
      final original = fields(tester).first.controller;
      await tester.tap(find.text('Tétel hozzáadása'));
      await tester.pumpAndSettle();
      expect(fields(tester).map((f) => f.controller!.text), [
        'alma',
        '1',
        '',
        '1',
      ]);
      expect(canSave(tester), isFalse);
      await tester.enterText(find.byType(TextField).at(2), 'tej');
      await tester.pump();
      expect(canSave(tester), isTrue);
      expect(fields(tester).first.controller, same(original));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        find.text('Az importált lista módosításai elvesznek.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'valid corrected warning saves exact ordered canonical snapshot and closes',
    (tester) async {
      List<ShoppingItemInput>? received;
      await open(
        tester,
        addItems: (items) async {
          received = items;
        },
      );
      await preview(tester, 'vaj 25 dkg;1,234 l tej');
      await tester.enterText(find.byType(TextField).first, ' Vaj ');
      await tester.enterText(find.byType(TextField).at(1), '25');
      await tester.pump();
      expect(find.textContaining('Eredeti szöveg: vaj 25 dkg'), findsOneWidget);
      expect(canSave(tester), isTrue);
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(received, [
        (name: 'Vaj', quantity: 25.0, unit: 'db'),
        (name: 'tej', quantity: 1.234, unit: 'l'),
      ]);
      expect(() => received!.clear(), throwsUnsupportedError);
      expect(find.byType(ShoppingImportDialog), findsNothing);
      expect(
        find.text('2 tétel hozzáadva a bevásárlólistához.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'pending save locks fields removal close and duplicate submission',
    (tester) async {
      final completion = Completer<void>();
      var calls = 0;
      await open(
        tester,
        addItems: (_) {
          calls++;
          return completion.future;
        },
      );
      await preview(tester, 'alma');
      final submit = tester.widget<FilledButton>(save).onPressed!;
      submit();
      submit();
      await tester.pump();
      expect(calls, 1);
      expect(fields(tester).every((field) => field.enabled == false), isTrue);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Tétel törlése',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Tétel hozzáadása'),
            )
            .onPressed,
        isNull,
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Megszakítod az importálást?'), findsNothing);
      expect(find.byType(ShoppingImportDialog), findsOneWidget);
      completion.complete();
      await tester.pumpAndSettle();
      expect(find.byType(ShoppingImportDialog), findsNothing);
    },
  );

  testWidgets('save error keeps edited data and permits retry', (tester) async {
    var calls = 0;
    await open(
      tester,
      addItems: (_) async {
        if (++calls == 1) throw StateError('test failure');
      },
    );
    await preview(tester, 'alma');
    await tester.enterText(find.byType(TextField).first, 'piros alma');
    await tester.pump();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.byType(ShoppingImportDialog), findsOneWidget);
    expect(fields(tester).first.controller!.text, 'piros alma');
    expect(
      find.text('Nem sikerült hozzáadni a tételeket. Próbáld újra.'),
      findsOneWidget,
    );
    expect(canSave(tester), isTrue);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.byType(ShoppingImportDialog), findsNothing);
  });

  testWidgets('input enables processing only for non-whitespace text', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Bevásárlólista importálása'), findsOneWidget);
    final button = find.widgetWithText(FilledButton, 'Feldolgozás');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tester.enterText(input, '  ');
    await tester.pump();
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tester.enterText(input, 'alma');
    await tester.pump();
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
  });
  testWidgets(
    'parser preview preserves order precision defaults and unit list',
    (tester) async {
      await open(tester);
      await preview(tester, '1,5 kg alma;1,234 l tej;kenyér');
      expect(find.text('Import előnézet'), findsOneWidget);
      expect(fields(tester).map((f) => f.controller!.text), [
        'alma',
        '1,5',
        'tej',
        '1,234',
        'kenyér',
        '1',
      ]);
      final dropdowns = tester
          .widgetList<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .toList();
      expect(dropdowns.map((d) => d.initialValue), ['kg', 'l', 'db']);
      final dropdown = tester
          .widgetList<DropdownButton<String>>(
            find.byType(DropdownButton<String>),
          )
          .first;
      expect(dropdown.items!.map((i) => i.value), shoppingUnits);
      expect(dropdown.menuMaxHeight, 240);
      expect(dropdown.isExpanded, true);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(
                FilledButton,
                'Hozzáadás a bevásárlólistához',
              ),
            )
            .onPressed,
        isNotNull,
      );
      expect(
        tester.takeException(),
        isNull,
      ); // No Firebase initialization or mocks.
    },
  );
  testWidgets('invalid and ambiguous parser drafts remain visible', (
    tester,
  ) async {
    await open(tester);
    await preview(tester, '0 kg alma;tej 1 2');
    expect(fields(tester).map((f) => f.controller!.text), [
      'alma',
      '0',
      'tej 1 2',
      '',
    ]);
    expect(
      find.textContaining('A felismerés javítást igényel.'),
      findsNWidgets(2),
    );
  });
  for (final text in [
    '-;•',
    'a' * 20001,
    List.filled(201, 'alma').join('\n'),
  ]) {
    testWidgets('processing handles empty results or limits ${text.length}', (
      tester,
    ) async {
      await open(tester);
      await preview(tester, text);
      expect(find.text('Bevásárlólista importálása'), findsOneWidget);
      expect(tester.widget<TextField>(input).decoration!.errorText, isNotNull);
      expect(tester.widget<TextField>(input).controller!.text, text);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('empty step one closes immediately on X or back', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Bezárás'));
    await tester.pumpAndSettle();
    expect(find.byType(ShoppingImportDialog), findsNothing);
    await tester.tap(find.text('Importálás'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ShoppingImportDialog), findsNothing);
  });
  testWidgets('nonempty input is protected and cancel preserves text', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(input, 'alma');
    await tester.pump();
    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();
    expect(find.byType(ShoppingImportDialog), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('A beillesztett lista elveszik.'), findsOneWidget);
    await tester.tap(find.text('Mégsem'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(input).controller!.text, 'alma');
    await tester.tap(find.byTooltip('Bezárás'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kilépés'));
    await tester.pumpAndSettle();
    expect(find.byType(ShoppingImportDialog), findsNothing);
  });
  testWidgets('preview protects edits and controller identity across rebuild', (
    tester,
  ) async {
    await open(tester);
    await preview(tester, 'kenyér');
    final controller = fields(tester).first.controller!;
    await tester.enterText(find.byType(TextField).first, 'Barna kenyér');
    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      find.text('Az importált lista módosításai elvesznek.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Mégsem'));
    await tester.pumpAndSettle();
    // Unit selection triggers a dialog setState, without recreating rows.
    final dropdown = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>),
    );
    dropdown.onChanged!('csomag');
    await tester.pump();
    expect(fields(tester).first.controller, same(controller));
    expect(controller.text, 'Barna kenyér');
    await tester.tap(find.byTooltip('Bezárás'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kilépés'));
    await tester.pumpAndSettle();
    expect(find.byType(ShoppingImportDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'small viewport keyboard and many long rows scroll without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await open(tester);
      await preview(
        tester,
        List.generate(
          30,
          (i) => '1 konzerv Nagyon hosszú hozzávalónév több szóval $i termék',
        ).join('\n'),
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(TextField).last);
      await tester.enterText(find.byType(TextField).last, '2,5');
      await tester.pumpAndSettle();
      expect(fields(tester).last.controller!.text, '2,5');
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Hozzáadás a bevásárlólistához'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
  for (final width in [320.0, 600.0]) {
    testWidgets('single editing row at width $width keeps fields independent', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await open(tester);
      await preview(
        tester,
        '1 konzerv Nagyon hosszú terméknév amely nem fér el;vaj 25 dkg',
      );
      final textFields = find.byType(TextField);
      final units = find.byType(DropdownButtonFormField<String>);
      for (var row = 0; row < 2; row++) {
        final nameRect = tester.getRect(textFields.at(row * 2));
        final quantityRect = tester.getRect(textFields.at(row * 2 + 1));
        final unitRect = tester.getRect(units.at(row));
        expect(quantityRect.top, closeTo(nameRect.top, 1));
        expect(unitRect.top, closeTo(nameRect.top, 1));
        expect(quantityRect.height, closeTo(nameRect.height, 1));
        expect(unitRect.height, closeTo(nameRect.height, 1));
        expect(nameRect.right, lessThan(quantityRect.left));
        expect(quantityRect.right, lessThan(unitRect.left));
        expect(nameRect.width, greaterThan(quantityRect.width));
        expect(tester.widget<TextField>(textFields.at(row * 2)).maxLines, 1);
      }
      final warning = find.textContaining(
        'A felismerés javítást igényel. Eredeti szöveg: vaj 25 dkg',
      );
      expect(warning, findsOneWidget);
      expect(
        tester.getTopLeft(warning).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(textFields.at(2)).dy),
      );
      final controllers = fields(tester).map((f) => f.controller).toList();
      await tester.enterText(textFields.first, 'Módosított hosszú név');
      await tester.enterText(textFields.at(1), '1,234');
      // Open the real compact dropdown and choose a long unit.
      await tester.tap(units.first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('csomag').last);
      await tester.pumpAndSettle();
      expect(fields(tester).map((f) => f.controller!.text), [
        'Módosított hosszú név',
        '1,234',
        'vaj 25 dkg',
        '',
      ]);
      for (var i = 0; i < controllers.length; i++) {
        expect(fields(tester)[i].controller, same(controllers[i]));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
