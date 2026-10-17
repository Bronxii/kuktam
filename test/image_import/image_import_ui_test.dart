import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/image_import/android_image_picker.dart';
import 'package:kuktam/image_import/image_import_controller.dart';
import 'package:kuktam/image_import/image_import_model.dart';
import 'package:kuktam/image_import/image_import_screen.dart';
import 'image_import_controller_test.dart'
    show FakePicker, FakePreparation, selection;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final n in [1, 3, 5]) {
    testWidgets(
      '$n selected shows full cost and local-only result without Pro host',
      (tester) async {
        final session = ValueNotifier(0);
        final picker = FakePicker()..next = selection(n);
        final c = ImageImportController(
          picker: picker,
          preparation: FakePreparation(),
          validateSession: () {},
          sessionChanges: session,
        );
        await tester.pumpWidget(
          MaterialApp(home: ImageImportScreen(controller: c)),
        );
        await tester.tap(find.text('Képek hozzáadása'));
        await tester.pumpAndSettle();
        expect(find.text('$n kép kiválasztva'), findsOneWidget);
        expect(find.text('Feldolgozás költsége: $n kredit'), findsOneWidget);
        expect(c.state, ImageImportState.readyToImport);
        await tester.scrollUntilVisible(
          find.text('Importálás – $n kredit'),
          200,
        );
        await tester.tap(find.text('Importálás – $n kredit'));
        await tester.pumpAndSettle();
        expect(c.state, ImageImportState.processingPlaceholder);
        expect(c.credits.balance, 20);
        expect(
          find.textContaining('AI-feldolgozás nem indult'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        session.dispose();
      },
    );
  }
  testWidgets(
    'narrow display, remove/reorder updates cost, cancellation disposes',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = ValueNotifier(0);
      final picker = FakePicker()..next = selection(3);
      final prep = FakePreparation();
      final c = ImageImportController(
        picker: picker,
        preparation: prep,
        validateSession: () {},
        sessionChanges: session,
      );
      await tester.pumpWidget(
        MaterialApp(home: ImageImportScreen(controller: c)),
      );
      await tester.tap(find.text('Képek hozzáadása'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Kép lejjebb').first);
      await tester.pumpAndSettle();
      expect(c.images.first.id, '1');
      expect(c.creditCost, 3);
      await tester.tap(find.byTooltip('Kép eltávolítása').first);
      await tester.pumpAndSettle();
      expect(find.text('Feldolgozás költsége: 2 kredit'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(picker.released.toSet(), {'0', '1', '2'});
      session.dispose();
    },
  );
  testWidgets('invalid image visible and whole import disabled', (
    tester,
  ) async {
    final session = ValueNotifier(0);
    final picker = FakePicker()..next = selection(2);
    final prep = FakePreparation()..fail = '1';
    final c = ImageImportController(
      picker: picker,
      preparation: prep,
      validateSession: () {},
      sessionChanges: session,
    );
    await tester.pumpWidget(
      MaterialApp(home: ImageImportScreen(controller: c)),
    );
    await tester.tap(find.text('Képek hozzáadása'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.textContaining('2. kép: Sérült'), 200);
    expect(find.textContaining('2. kép: Sérült'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Importálás – 2 kredit'), 200);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Importálás – 2 kredit'),
    );
    expect(button.onPressed, isNull);
    expect(c.operation, isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
  testWidgets('session changes clear thumbnails and disable interaction', (
    tester,
  ) async {
    final session = ValueNotifier(0);
    final picker = FakePicker()..next = selection(1);
    final c = ImageImportController(
      picker: picker,
      preparation: FakePreparation(),
      validateSession: () {
        if (session.value != 0) throw StateError('session');
      },
      sessionChanges: session,
    );
    await tester.pumpWidget(
      MaterialApp(home: ImageImportScreen(controller: c)),
    );
    await tester.tap(find.text('Képek hozzáadása'));
    await tester.pumpAndSettle();
    session.value = 1;
    await tester.pumpAndSettle();
    expect(find.textContaining('A munkamenet megváltozott'), findsOneWidget);
    expect(c.images, isEmpty);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
  test(
    'platform picker maps only private files, releases by ID, cancel',
    () async {
      const channel = MethodChannel('test/image-import');
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'pick'
            ? [
                {'id': 'one', 'path': 'private/copy'},
                {'id': 'bad', 'error': 'format'},
              ]
            : null;
      });
      const picker = AndroidImageImportPicker(channel: channel);
      final images = await picker.pick(3, const ImageImportPolicy());
      expect(images.length, 2);
      expect(images[1].failure!.code, 'format');
      expect(calls.first.arguments, {
        'remaining': 3,
        'maxBytes': 20 * 1024 * 1024,
      });
      await picker.release(images);
      expect(calls.last.arguments, ['one', 'bad']);
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      expect(await picker.pick(1, const ImageImportPolicy()), isEmpty);
      messenger.setMockMethodCallHandler(channel, null);
    },
  );
  test(
    'Android source contract: separate channel, no inbound image or permissions',
    () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      expect(manifest, isNot(contains('android.permission.READ_MEDIA_IMAGES')));
      expect(
        manifest,
        isNot(contains('android.permission.READ_EXTERNAL_STORAGE')),
      );
      expect(manifest, isNot(contains('android:mimeType="image/')));
      final native = File(
        'android/app/src/main/kotlin/com/bronxii/kuktam/ImageImportPicker.kt',
      ).readAsStringSync();
      expect(native, contains('MediaStore.ACTION_PICK_IMAGES'));
      expect(native, contains('Intent.ACTION_OPEN_DOCUMENT'));
      expect(native, contains('ImageInputCopy.validCount(count, remaining)'));
      expect(native, contains('uri.scheme != "content"'));
    },
  );
}
