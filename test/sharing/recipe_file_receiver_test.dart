import 'dart:io';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:kuktam/settings/settings_screen.dart';
import '../auth/auth_qa_test.dart' show UiRepo;
import 'dart:collection';
import 'dart:async';
import 'package:kuktam/core/account_deletion_signal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/sharing/recipe_file_receiver.dart';
import 'package:kuktam/sharing/recipe_share_codec.dart';
import 'package:kuktam/sharing/text_share_controller.dart';
import 'package:kuktam/home/presentation/screens/main_screen.dart';
import 'package:kuktam/recipes/presentation/screens/add_recipe_screen.dart';
import 'package:kuktam/recipes/presentation/screens/recipe_details_screen.dart';
import 'package:kuktam/features/auth/presentation/widgets/auth_gate.dart';
import 'package:kuktam/features/auth/data/repositories/auth_repository.dart';
import '../recipes/recipe_core_test.dart' show CoreRepository, coreField;
import '../shopping/shopping_core_qa_test.dart' show ShoppingFake;
import '../auth/email_verification_test.dart' show TestAuth, TestUser;
import '../support/feature_access.dart';
import 'recipe_share_codec_test.dart' show sampleRecipe;

void receive(RecipeFileReceiver r, String id) {
  r.accept({'id': id, 'stage': 'begin'});
  r.accept({'id': id, 'bytes': RecipeShareCodec.encode(sampleRecipe)});
}

MainScreen screen(
  RecipeFileReceiver r,
  TextShareNavigationObserver observer,
  CoreRepository repo,
) => MainScreen(
  recipeFiles: r,
  textShares: TextShareController(),
  shareNavigation: observer,
  recipeRepository: repo,
  shoppingRepository: ShoppingFake(),
  tabBodies: const [Text('Recipes'), Text('Shopping'), Text('Cook')],
);
Future<void> mount(
  WidgetTester t,
  RecipeFileReceiver r,
  CoreRepository repo,
) async {
  final observer = TextShareNavigationObserver();
  await t.pumpWidget(
    withFreeAccess(
      MaterialApp(
        navigatorObservers: [observer],
        home: screen(r, observer, repo),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> save(WidgetTester t) async {
  final button = find.text('Mentés');
  await t.scrollUntilVisible(
    button,
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await t.pumpAndSettle();
  await t.tap(button);
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('manifest generic MIME is only suffix constrained VIEW', () {
    final xml = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(xml, isNot(contains('mimeType="*/*"')));
    expect(xml, isNot(contains('mimeType="application/*"')));
    for (final match in RegExp(
      r'<intent-filter>[\s\S]*?</intent-filter>',
    ).allMatches(xml)) {
      final filter = match.group(0)!;
      if (filter.contains('mimeType="application/json"') ||
          filter.contains('mimeType="application/octet-stream"')) {
        expect(filter, contains('android.intent.action.VIEW'));
        expect(filter, isNot(contains('android.intent.action.SEND')));
        expect(filter, contains('scheme="content"'));
        expect(filter, contains('host="*"'));
        expect(filter, contains('pathSuffix=".kuktamrecipe"'));
        final paths = RegExp(r'pathPattern="([^"]+)"').allMatches(filter);
        expect(paths, isNotEmpty);
        for (final path in paths) {
          expect(path.group(1), endsWith('.kuktamrecipe'));
        }
      }
    }
  });
  testWidgets('Free Settings picker returns to existing new recipe editor', (
    t,
  ) async {
    PackageInfo.setMockInitialValues(
      appName: 'Kuktám',
      packageName: 'com.bronxii.kuktam',
      version: '1',
      buildNumber: '1',
      buildSignature: '',
    );
    const channel = MethodChannel('kuktam/recipe_file');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final r = RecipeFileReceiver()..updateSession('a');
    final repo = CoreRepository();
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => RecipeShareCodec.encode(sampleRecipe),
    );
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await mount(t, r, repo);
    final navigator = t.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              SettingsScreen(authRepository: UiRepo(), recipeFiles: r),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Kuktám recept importálása'));
    await t.pumpAndSettle();
    expect(find.byType(AddRecipeScreen), findsOneWidget);
    expect(find.text(sampleRecipe.name), findsOneWidget);
    expect(repo.saves, 0);
    await t.pumpWidget(const SizedBox());
    r.dispose();
  });
  test('explicit picker shares strict decoder and pending queue', () async {
    const channel = MethodChannel('kuktam/recipe_file');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final r = RecipeFileReceiver()..updateSession('a');
    addTearDown(r.dispose);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'pick');
      return RecipeShareCodec.encode(sampleRecipe);
    });
    expect(await r.pickFile(), isTrue);
    expect(r.take()!.name, sampleRecipe.name);
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(await r.pickFile(), isFalse);
    expect(r.hasPending, isFalse);
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => Uint8List.fromList([123]),
    );
    await expectLater(r.pickFile(), throwsA(isA<RecipeShareFailure>()));
    expect(r.hasPending, isFalse);
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'size'),
    );
    await expectLater(r.pickFile(), throwsA(isA<RecipeShareFailure>()));
  });
  test('picker busy and session switch fence pending selection', () async {
    const channel = MethodChannel('kuktam/recipe_file');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final r = RecipeFileReceiver()..updateSession('a');
    addTearDown(r.dispose);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final pending = Completer<Uint8List>();
    messenger.setMockMethodCallHandler(channel, (_) => pending.future);
    final first = r.pickFile();
    expect(await r.pickFile(), isFalse);
    r.updateSession('b');
    final check = expectLater(first, throwsA(isA<RecipeShareFailure>()));
    pending.complete(RecipeShareCodec.encode(sampleRecipe));
    await check;
    expect(r.hasPending, isFalse);
  });
  test(
    'event dedupe, FIFO, equal content separate events and once-only take',
    () {
      final r = RecipeFileReceiver();
      addTearDown(r.dispose);
      receive(r, 'a');
      receive(r, 'a');
      receive(r, 'b');
      expect(r.take()!.name, sampleRecipe.name);
      expect(r.take()!.name, sampleRecipe.name);
      expect(r.take(), isNull);
    },
  );
  test('bounded queue, malformed events and read errors', () {
    final r = RecipeFileReceiver();
    addTearDown(r.dispose);
    r.accept({});
    r.accept({'id': '', 'stage': 'begin'});
    expect(r.hasPending, isFalse);
    r.accept({'id': 'err', 'stage': 'begin'});
    r.accept({'id': 'err', 'error': 'read'});
    expect(r.takeNotice(), contains('olvasható'));
    for (var i = 0; i < 11; i++) {
      receive(r, '$i');
    }
    expect(r.takeNotice(), contains('várakozó'));
    for (var i = 0; i < 10; i++) {
      expect(r.take(), isNotNull);
    }
    expect(r.take(), isNull);
  });
  test(
    'login adopts pending; logout/ABA clears pending and in-flight reads',
    () {
      final r = RecipeFileReceiver();
      addTearDown(r.dispose);
      receive(r, 'login');
      r.updateSession('a');
      expect(r.take(), isNotNull);
      final generation = r.generation;
      receive(r, 'queued');
      r.accept({'id': 'reading', 'stage': 'begin'});
      r.updateSession(null);
      r.updateSession('b');
      r.updateSession('a');
      r.accept({
        'id': 'reading',
        'bytes': RecipeShareCodec.encode(sampleRecipe),
      });
      expect(r.take(), isNull);
      expect(() => r.check(generation), throwsA(isA<RecipeShareFailure>()));
    },
  );
  test('current SDK identity fences before delayed auth stream delivery', () {
    String? uid = 'a';
    final r = RecipeFileReceiver();
    addTearDown(r.dispose);
    r.bindSession(const Stream.empty(), uid, currentUid: () => uid);
    final generation = r.generation;
    uid = 'b';
    expect(() => r.check(generation), throwsA(isA<RecipeShareFailure>()));
  });
  test('local account deletion fences queued and active imports', () {
    final r = RecipeFileReceiver()..updateSession('a');
    addTearDown(r.dispose);
    receive(r, 'delete');
    final generation = r.generation;
    AccountDeletionSignal.begin();
    AccountDeletionSignal.end();
    expect(r.hasPending, isFalse);
    expect(() => r.check(generation), throwsA(isA<RecipeShareFailure>()));
  });
  testWidgets(
    'bridge cold and new event, unknown data never becomes text import',
    (t) async {
      const channel = MethodChannel('kuktam/recipe_file');
      final queue = Queue<Object>.of([
        {'id': 'a', 'stage': 'begin'},
        {'id': 'a', 'bytes': RecipeShareCodec.encode(sampleRecipe)},
      ]);
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => queue.isEmpty ? null : queue.removeFirst(),
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final r = RecipeFileReceiver(channel: channel);
      addTearDown(r.dispose);
      await r.start();
      expect(r.take(), isNotNull);
      await r.start();
      expect(r.take(), isNull);
      queue.addAll([
        {'id': 'b', 'stage': 'begin'},
        {'id': 'b', 'bytes': RecipeShareCodec.encode(sampleRecipe)},
      ]);
      await t.binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('pending'),
        ),
        (_) {},
      );
      await t.pump();
      expect(r.take(), isNotNull);
    },
  );
  testWidgets(
    'Free cold import prefills direct editor; explicit create preserves fields',
    (t) async {
      final r = RecipeFileReceiver()..updateSession('a');
      receive(r, 'cold');
      final repo = CoreRepository();
      await mount(t, r, repo);
      expect(find.byType(AddRecipeScreen), findsOneWidget);
      expect(repo.saves, 0);
      expect(
        t.widget<AddRecipeScreen>(find.byType(AddRecipeScreen)).recipe,
        isNull,
      );
      expect(
        t.widget<TextField>(coreField('Recept neve')).controller!.text,
        sampleRecipe.name,
      );
      await save(t);
      expect(repo.saves, 1);
      expect(repo.updates, 0);
      expect(repo.recipes.single.id, isNull);
      expect(repo.recipes.single.toMap(), sampleRecipe.toMap());
      await t.pumpWidget(const SizedBox());
      r.dispose();
    },
  );
  testWidgets(
    'warm duplicate event and second event wait; cancel writes nothing',
    (t) async {
      final r = RecipeFileReceiver()..updateSession('a');
      final repo = CoreRepository();
      await mount(t, r, repo);
      receive(r, 'one');
      await t.pumpAndSettle();
      receive(r, 'one');
      receive(r, 'two');
      await t.pumpAndSettle();
      expect(find.byType(AddRecipeScreen), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.byType(AddRecipeScreen), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.byType(AddRecipeScreen), findsNothing);
      expect(repo.saves, 0);
      await t.pumpWidget(const SizedBox());
      r.dispose();
    },
  );
  testWidgets(
    'duplicate name blocks overwrite; explicit rename creates new recipe',
    (t) async {
      final r = RecipeFileReceiver()..updateSession('a');
      receive(r, 'dup');
      final repo = CoreRepository()..recipes.add(sampleRecipe);
      await mount(t, r, repo);
      await save(t);
      expect(repo.saves, 0);
      expect(repo.updates, 0);
      expect(find.text('Már létezik ilyen nevű recept!'), findsOneWidget);
      await t.pump(const Duration(seconds: 5));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        coreField('Recept neve'),
        -250,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.enterText(coreField('Recept neve'), 'Másik recept');
      await save(t);
      expect(repo.saves, 1);
      expect(repo.recipes.first, sampleRecipe);
      expect(repo.recipes.last.name, 'Másik recept');
      await t.pumpWidget(const SizedBox());
      r.dispose();
    },
  );
  testWidgets('stale open editor cannot save after account switch', (t) async {
    final r = RecipeFileReceiver()..updateSession('a');
    receive(r, 'one');
    final repo = CoreRepository();
    await mount(t, r, repo);
    r.updateSession('b');
    await save(t);
    expect(repo.saves, 0);
    expect(repo.checks, 0);
    await t.pumpWidget(const SizedBox());
    r.dispose();
  });
  testWidgets('logged-out input waits and login opens editor', (t) async {
    final r = RecipeFileReceiver();
    receive(r, 'login');
    final observer = TextShareNavigationObserver();
    final auth = TestAuth(TestUser(true, ['password']));
    final repo = CoreRepository();
    r.bindSession(auth.changes.stream.map((u) => u?.uid), null);
    await t.pumpWidget(
      withFreeAccess(
        MaterialApp(
          navigatorObservers: [observer],
          home: AuthGate(
            authRepository: AuthRepository(firebaseAuth: auth),
            recipeFiles: r,
            mainBuilder: (_) => screen(r, observer, repo),
          ),
        ),
      ),
    );
    auth.changes.add(null);
    await t.pumpAndSettle();
    expect(find.byType(AddRecipeScreen), findsNothing);
    expect(r.hasPending, isTrue);
    expect(
      find.text(
        'A recept megnyitásához jelentkezz be. Utána folytatjuk az importot.',
      ),
      findsOneWidget,
    );
    auth.changes.add(auth.loginUser);
    await t.pumpAndSettle();
    expect(find.byType(AddRecipeScreen), findsOneWidget);
    expect(repo.saves, 0);
    await t.pumpWidget(const SizedBox());
    r.dispose();
    await auth.changes.close();
  });
  testWidgets(
    'outbound Kuktam option retains existing text share and is Free',
    (t) async {
      var calls = 0;
      await t.pumpWidget(
        withFreeAccess(
          MaterialApp(
            home: RecipeDetailsScreen(
              recipe: sampleRecipe,
              recipeRepository: CoreRepository(),
              structuredShare: (recipe) async {
                calls++;
                expect(recipe, sampleRecipe);
              },
            ),
          ),
        ),
      );
      expect(t.widget<AppBar>(find.byType(AppBar)).actions, hasLength(1));
      await t.tap(find.byTooltip('Recept műveletek'));
      await t.pumpAndSettle();
      for (final label in [
        'Megosztás Kuktámmal',
        'Megosztás szövegként',
        'Szerkesztés',
        'Törlés',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      await t.tap(find.text('Megosztás Kuktámmal'));
      await t.pumpAndSettle();
      expect(calls, 1);
    },
  );
}
