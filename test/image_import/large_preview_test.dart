import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kuktam/image_import/image_import_controller.dart';
import 'package:kuktam/image_import/image_import_model.dart';
import 'package:kuktam/image_import/image_import_screen.dart';
import 'package:kuktam/image_import/image_inspection_screen.dart';
import 'image_import_controller_test.dart'
    show FakePicker, FakePreparation, selection;

class PreviewPreparation extends FakePreparation {
  PreviewPreparation(this.directory, {this.landscape = false});
  final Directory directory;
  final bool landscape;
  @override
  Future<PreparedImportImage> prepare(
    SelectedImportImage image,
    ImageImportPolicy policy,
  ) async {
    calls.add(image.id);
    final width = landscape ? 1200 : 500, height = landscape ? 500 : 1200;
    final picture = img.fill(
      img.Image(width: width, height: height),
      color: img.ColorRgb8(250, 240, 220),
    );
    for (var y = 40; y < height - 60; y += 70) {
      img.drawString(
        picture,
        'Recipe ${image.id} - section $y',
        font: img.arial24,
        x: 20,
        y: y,
        color: img.ColorRgb8(30, 30, 30),
      );
    }
    final file = File('${directory.path}/${image.id}.jpg')
      ..writeAsBytesSync(img.encodeJpg(picture));
    return PreparedImportImage(
      id: image.id,
      localFile: file.path,
      byteLength: file.lengthSync(),
      width: width,
      height: height,
    );
  }
}

void main() {
  late Directory directory;
  late ValueNotifier<int> session;
  late FakePicker picker;
  late PreviewPreparation prep;
  late ImageImportController c;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('preview-test-');
    session = ValueNotifier(0);
    picker = FakePicker();
  });
  tearDown(() {
    session.dispose();
    directory.deleteSync(recursive: true);
  });
  Future<void> show(
    WidgetTester tester, {
    int count = 5,
    bool landscape = false,
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    prep = PreviewPreparation(directory, landscape: landscape);
    c = ImageImportController(
      picker: picker,
      preparation: prep,
      validateSession: () {
        if (session.value != 0) throw StateError('changed');
      },
      sessionChanges: session,
    );
    picker.next = selection(count);
    await c.add();
    await c.prepare();
    await tester.pumpWidget(
      MaterialApp(home: ImageImportScreen(controller: c)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets(
    'portrait cards are 33 percent viewport and one per row; all five scroll',
    (tester) async {
      await show(tester);
      for (var i = 0; i < 5; i++) {
        final preview = find.byKey(ValueKey('image-preview-$i'));
        await tester.scrollUntilVisible(preview, 180);
        await tester.pumpAndSettle();
        expect(tester.getSize(preview).height, closeTo(844 * .33, .1));
        expect(tester.getSize(preview).width, greaterThan(320));
        final image = tester.widget<Image>(
          find.descendant(of: preview, matching: find.byType(Image)),
        );
        expect(image.fit, BoxFit.contain);
        expect(
          find.descendant(
            of: find.byKey(ValueKey('image-card-$i')),
            matching: find.text('${i + 1}. kép'),
          ),
          findsOneWidget,
        );
      }
      expect(c.creditCost, 5);
      expect(tester.takeException(), isNull);
      await close(tester);
    },
  );
  for (final size in [const Size(320, 568), const Size(1200, 1600)]) {
    testWidgets('responsive single portrait $size bounded and not thumbnail', (
      tester,
    ) async {
      await show(tester, count: 1, size: size);
      final preview = find.byKey(const ValueKey('image-preview-0'));
      await tester.scrollUntilVisible(preview, 150);
      final height = tester.getSize(preview).height;
      expect(height, greaterThan(180));
      expect(height, lessThanOrEqualTo(480));
      expect(tester.takeException(), isNull);
      await close(tester);
    });
  }
  testWidgets(
    'landscape containment uses natural width ratio, no tall empty card',
    (tester) async {
      await show(tester, count: 1, landscape: true);
      final preview = find.byKey(const ValueKey('image-preview-0'));
      final size = tester.getSize(preview);
      expect(size.height, closeTo(size.width / (1200 / 500), .1));
      expect(
        tester
            .widget<Image>(
              find.descendant(of: preview, matching: find.byType(Image)),
            )
            .fit,
        BoxFit.contain,
      );
      await close(tester);
    },
  );
  testWidgets('viewer correct page navigation zoom close preserve all state', (
    tester,
  ) async {
    await show(tester);
    final before = c.prepared;
    final credit = c.creditCost;
    final preview = find.byKey(const ValueKey('image-preview-1'));
    await tester.scrollUntilVisible(preview, 180);
    await tester.pumpAndSettle();
    await tester.ensureVisible(preview);
    await tester.pumpAndSettle();
    await tester.tap(preview);
    await tester.pumpAndSettle();
    expect(find.byType(ImageInspectionScreen), findsOneWidget);
    expect(find.text('2 / 5'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    final provider =
        tester
                .widget<Image>(
                  find.descendant(
                    of: find.byType(ImageInspectionScreen),
                    matching: find.byType(Image),
                  ),
                )
                .image
            as FileImage;
    expect(provider.file.path, before[1].localFile);
    await tester.tap(find.byTooltip('Következő kép'));
    await tester.pumpAndSettle();
    expect(find.text('3 / 5'), findsOneWidget);
    await tester.tap(find.byTooltip('Előző kép'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 5'), findsOneWidget);
    await tester.tap(find.byTooltip('Előnézet bezárása'));
    await tester.pumpAndSettle();
    expect(c.prepared, before);
    expect(c.creditCost, credit);
    expect(c.credits.balance, 20);
    expect(prep.calls.length, 5);
    expect(c.operation, isNull);
    expect(find.byType(ImageInspectionScreen), findsNothing);
    await close(tester);
  });
  testWidgets(
    'reorder actual card numbers operation and viewer order; no new preparation',
    (tester) async {
      await show(tester, count: 3);
      await tester.tap(find.byTooltip('Kép lejjebb').first);
      await tester.pumpAndSettle();
      expect(c.images.map((i) => i.id), ['1', '0', '2']);
      expect(c.creditCost, 3);
      final card = find.byKey(const ValueKey('image-card-1'));
      expect(
        find.descendant(of: card, matching: find.text('1. kép')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('image-preview-1')));
      await tester.pumpAndSettle();
      expect(find.text('1 / 3'), findsOneWidget);
      await tester.tap(find.byTooltip('Következő kép'));
      await tester.pumpAndSettle();
      final image = tester.widget<Image>(
        find.descendant(
          of: find.byType(ImageInspectionScreen),
          matching: find.byType(Image),
        ),
      );
      expect((image.image as FileImage).file.path, endsWith('0.jpg'));
      await tester.tap(find.byTooltip('Előnézet bezárása'));
      await tester.pumpAndSettle();
      c.start();
      expect(c.operation!.images.map((i) => i.id), ['1', '0', '2']);
      expect(prep.calls.length, 3);
      await close(tester);
    },
  );
  testWidgets(
    'remove five to four and add back five preserves prepared artifacts',
    (tester) async {
      await show(tester);
      final retained = c.prepared.skip(1).toList();
      await tester.tap(find.byTooltip('Kép eltávolítása').first);
      await tester.pumpAndSettle();
      expect(c.creditCost, 4);
      expect(c.prepared, retained);
      picker.next = selection(1, 9);
      await tester.scrollUntilVisible(find.text('Képek hozzáadása'), 250);
      await tester.tap(find.text('Képek hozzáadása'));
      await tester.pumpAndSettle();
      expect(c.creditCost, 5);
      expect(c.prepared.take(4), retained);
      expect(prep.calls.length, 6);
      expect(c.credits.balance, 20);
      await close(tester);
    },
  );
  testWidgets('session invalidation removes full screen pixels and old state', (
    tester,
  ) async {
    await show(tester, count: 1);
    await tester.tap(find.byKey(const ValueKey('image-preview-0')));
    await tester.pumpAndSettle();
    session.value = 1;
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
    expect(c.prepared, isEmpty);
    expect(find.textContaining('A munkamenet megváltozott'), findsOneWidget);
    await close(tester);
  });
}
