import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:kuktam/core/account_deletion_signal.dart';
import 'package:kuktam/export/domain/recipe_export.dart';
import 'package:kuktam/export/domain/recipe_export_formatter.dart';
import 'package:kuktam/export/domain/recipe_export_encoder.dart';
import 'package:kuktam/export/data/recipe_export_source.dart';
import 'package:kuktam/export/data/export_file_gateway.dart';
import 'package:kuktam/export/presentation/recipe_export_controller.dart';
import 'package:kuktam/settings/settings_screen.dart';
import 'package:kuktam/recipes/domain/models/recipe.dart';
import '../auth/auth_qa_test.dart' show UiRepo;
import '../support/feature_access.dart';

Map<String, dynamic> data({String name = 'Túrós lepény'}) => {
  'name': name,
  'ingredients': [
    {'name': 'túró', 'quantity': 500.0, 'unit': 'g'},
    {'name': 'tej', 'quantity': 0.25, 'unit': 'l'},
  ],
  'spices': [
    {'name': 'só'},
    {'name': 'bors'},
  ],
  'preparation': 'Keverd össze.\nSüsd készre.',
  'uid': 'PRIVATE_UID',
  'email': 'PRIVATE_EMAIL',
  'createdAt': 'PRIVATE_TIME',
  'updatedAt': 'PRIVATE_TIME',
  'entitlement': true,
  'grant': 'PRIVATE_GRANT',
  'billing': {},
  'purchaseToken': 'PRIVATE_TOKEN',
  'HMAC': 'PRIVATE_KEY',
  'accountLifecycle': 'PRIVATE_STATE',
};
ExportRecipe recipe() =>
    ExportRecipe.fromRecipe(Recipe.fromMap(data(), id: 'PRIVATE_DOC'));

class Port implements ExportReadPort {
  ExportSnapshot snapshot = ExportSnapshot([(id: 'private', data: data())]);
  Completer<void>? wait;
  Object? error;
  final calls = <String>[];
  @override
  Future<void> waitForPendingWrites() async {
    calls.add('wait');
    if (wait != null) await wait!.future;
  }

  @override
  Future<ExportSnapshot> serverRecipes(String uid) async {
    calls.add('server:$uid');
    if (error != null) throw error!;
    return snapshot;
  }
}

class SessionFixture {
  String? uid = 'a';
  final events = StreamController<String?>.broadcast(sync: true);
  late final session = ExportSession(
    currentUid: () => uid,
    users: events.stream,
  );
  void change(String? next) {
    uid = next;
    events.add(next);
  }

  void dispose() {
    session.dispose();
    events.close();
  }
}

class Files implements ExportFileGateway {
  int builds = 0, saves = 0, shares = 0, discards = 0, cancels = 0;
  bool saveResult = true, fail = false;
  Completer<void>? hold;
  @override
  Future<ExportArtifact> build(
    List<ExportRecipe> r,
    DateTime t,
    String v,
    String b,
  ) async {
    builds++;
    if (hold != null) await hold!.future;
    if (fail) throw const ExportFailure('build');
    return ExportArtifact('/fake', 'test.zip', r.length);
  }

  @override
  Future<bool> save(ExportArtifact a, void Function() check) async {
    check();
    saves++;
    if (fail) throw const ExportFailure('save');
    return saveResult;
  }

  @override
  Future<void> share(ExportArtifact a, void Function() check) async {
    check();
    shares++;
  }

  @override
  Future<void> discard(ExportArtifact a) async {
    discards++;
  }

  @override
  Future<void> cancel() async {
    cancels++;
  }
}

RecipeExportController controller(SessionFixture s, Port p, Files f) =>
    RecipeExportController(
      session: s.session,
      source: RecipeExportSource(p),
      files: f,
      packageInfo: () async => ('1.0.0', '1'),
      clock: () => DateTime.utc(2026, 10, 10, 12),
    );

void main() {
  test(
    'allowlist, exact JSON schema, ZIP UTF8 entries, order and lossless values',
    () {
      final dir = Directory.systemTemp.createTempSync('e1-test-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/export.zip');
      writeRecipeExport(
        path: file.path,
        recipes: [recipe()],
        time: DateTime.utc(2026, 10, 10, 12),
        appVersion: '1.0.0',
        appBuild: '1',
      );
      final archive = ZipDecoder().decodeBytes(
        file.readAsBytesSync(),
        verify: true,
      );
      final name = exportTextFileName('Túrós lepény', 1, 1);
      expect(archive.map((f) => f.name).toSet(), {
        'recipes.json',
        'export_info.txt',
        name,
      });
      String read(String path) =>
          utf8.decode(archive.findFile(path)!.content as List<int>);
      final json = read('recipes.json');
      expect(json.endsWith('\n'), isTrue);
      expect(json.startsWith('{\n  "format"'), isTrue);
      expect(json.contains('PRIVATE'), isFalse);
      expect(json.contains('\r'), isFalse);
      final parsed = jsonDecode(json) as Map;
      expect(parsed.keys.toSet(), {
        'format',
        'exportVersion',
        'exportedAt',
        'appVersion',
        'appBuild',
        'recipes',
      });
      expect(parsed['format'], 'kuktam.recipes');
      expect(parsed['exportVersion'], 1);
      expect(parsed['exportedAt'], '2026-10-10T12:00:00.000Z');
      expect(parsed['appVersion'], '1.0.0');
      expect(parsed['appBuild'], '1');
      final payload = (parsed['recipes'] as List).single as Map;
      expect(payload.keys.toSet(), {
        'textFile',
        'name',
        'ingredients',
        'spices',
        'preparation',
      });
      expect(payload['ingredients'], data()['ingredients']);
      expect(payload['spices'], data()['spices']);
      expect(payload['preparation'], data()['preparation']);
      expect(payload['textFile'], name);
      expect(
        read(name),
        'Túrós lepény\n\nHozzávalók:\n• túró – 500 g\n• tej – 0.25 l\n\nFűszerek:\n• só\n• bors\n\nElkészítés:\nKeverd össze.\nSüsd készre.\n\n──────────────\nKészült a Kuktám alkalmazással\n',
      );
      expect(read('export_info.txt'), contains('Receptek száma: 1'));
    },
  );
  test('empty recipes are a complete valid ZIP', () {
    final dir = Directory.systemTemp.createTempSync('e1-test-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/empty.zip');
    writeRecipeExport(
      path: file.path,
      recipes: [],
      time: DateTime.utc(2026),
      appVersion: 'v',
      appBuild: 'b',
    );
    final zip = ZipDecoder().decodeBytes(file.readAsBytesSync());
    expect(zip.length, 2);
    expect(
      jsonDecode(
        utf8.decode(zip.findFile('recipes.json')!.content as List<int>),
      )['recipes'],
      isEmpty,
    );
  });
  test('empty optional sections omitted only in TXT', () {
    final r = ExportRecipe(
      name: 'Üres',
      ingredients: [],
      spices: [],
      preparation: '',
    );
    expect(exportRecipeText(r), isNot(contains('Fűszerek:')));
    expect(exportRecipeText(r), isNot(contains('Elkészítés:')));
    expect(r.toJson('x')['spices'], isEmpty);
    expect(r.toJson('x')['preparation'], '');
  });
  for (final value in [double.nan, double.infinity, double.negativeInfinity]) {
    test('nonfinite quantity rejected $value', () {
      expect(
        () => ExportRecipe(
          name: 'x',
          ingredients: [
            RecipeIngredient(name: 'x', quantity: value, unit: 'g'),
          ],
          spices: [],
          preparation: '',
        ),
        throwsA(isA<ExportFailure>()),
      );
    });
  }
  for (final name in [
    '../a/b\\c:*?"<>|',
    '\u0000\u0009\u202e\u2066',
    '.... ',
    '',
    'Árvíztűrő tükörfúrógép',
    '😀' * 100,
    'a' * 500,
  ]) {
    test('filename safety $name', () {
      final path = exportTextFileName(name, 1, 2);
      expect(path.startsWith('receptek/000001-'), isTrue);
      final base = path.substring('receptek/000001-'.length, path.length - 4);
      expect(utf8.encode(base).length, lessThanOrEqualTo(120));
      expect(
        base,
        isNot(matches(RegExp(r'[/\\:*?"<>|\x00-\x1f\u202e\u2066]'))),
      );
      expect(path.split('/').length, 2);
      expect(path.split('/'), isNot(contains('..')));
      expect(exportTextFileName(name, 1, 2), path);
      expect(exportTextFileName(name, 2, 2), isNot(path));
    });
  }
  test('filename fallback accents and UTC name', () {
    expect(exportTextFileName(' ... ', 1, 1), 'receptek/000001-Recept.txt');
    expect(exportTextFileName('Túró. ', 1, 1), 'receptek/000001-Túró.txt');
    expect(
      exportArchiveName(DateTime.parse('2026-10-10T14:00:00+02:00')),
      'Kuktam-receptek-20261010-120000Z.zip',
    );
  });
  for (final count in [0, 1, 100]) {
    test(
      'server source all $count recipes, wait before server, no metadata',
      () async {
        final s = SessionFixture();
        addTearDown(s.dispose);
        final p = Port()
          ..snapshot = ExportSnapshot([
            for (var i = 0; i < count; i++)
              (id: '$i', data: data(name: 'Recept $i')),
          ]);
        final result = await RecipeExportSource(p).load(s.session);
        expect(result.length, count);
        expect(p.calls, ['wait', 'server:a']);
      },
    );
  }
  for (final bad in [
    'cache',
    'pending',
    'malformed',
    'unavailable',
    'timeout',
  ]) {
    test('no partial export on $bad', () async {
      final s = SessionFixture();
      addTearDown(s.dispose);
      final p = Port();
      if (bad == 'cache') p.snapshot = ExportSnapshot([], fromCache: true);
      if (bad == 'pending') {
        p.snapshot = ExportSnapshot([], pendingWrites: true);
      }
      if (bad == 'malformed') {
        p.snapshot = ExportSnapshot([
          (id: 'ok', data: data()),
          (id: 'bad', data: {'name': 'bad'}),
        ]);
      }
      if (bad == 'unavailable') p.error = Exception('private error');
      if (bad == 'timeout') p.wait = Completer<void>();
      await expectLater(
        RecipeExportSource(
          p,
          timeout: const Duration(milliseconds: 1),
        ).load(s.session),
        throwsA(isA<ExportFailure>()),
      );
    });
  }
  for (final change in ['logout', 'switch', 'aba', 'delete']) {
    test('session $change fences server source', () async {
      final s = SessionFixture();
      addTearDown(s.dispose);
      final p = Port()..wait = Completer<void>();
      final future = RecipeExportSource(p).load(s.session);
      if (change == 'delete') {
        AccountDeletionSignal.begin();
        AccountDeletionSignal.end();
      } else {
        s.change(change == 'logout' ? null : 'b');
        if (change == 'aba') s.change('a');
      }
      p.wait!.complete();
      await expectLater(future, throwsA(isA<ExportFailure>()));
      expect(p.calls, ['wait']);
    });
  }
  test('controller double tap, ready, cancel save, save, share', () async {
    final s = SessionFixture();
    final p = Port()..wait = Completer<void>();
    final f = Files();
    final c = controller(s, p, f);
    addTearDown(c.dispose);
    final running = c.start();
    await c.start();
    expect(c.busy, isTrue);
    p.wait!.complete();
    await running;
    expect(f.builds, 1);
    expect(c.phase, ExportPhase.ready);
    f.saveResult = false;
    await c.save();
    expect(c.message, contains('megszakítottad'));
    f.saveResult = true;
    await c.save();
    expect(c.message, contains('befejeződött'));
    await c.share();
    expect(f.shares, 1);
    expect(c.message, contains('fogadó'));
    f.fail = true;
    await c.save();
    expect(c.message, contains('nem sikerült'));
  });
  test('controller failure retry and stale build discard', () async {
    final s = SessionFixture();
    final p = Port()..error = Exception();
    final f = Files();
    final c = controller(s, p, f);
    addTearDown(c.dispose);
    await c.start();
    expect(c.phase, ExportPhase.failed);
    expect(f.builds, 0);
    p.error = null;
    f.hold = Completer<void>();
    final run = c.start();
    await Future<void>.delayed(Duration.zero);
    s.change('b');
    f.hold!.complete();
    await run;
    expect(c.artifact, isNull);
    expect(f.discards, 1);
  });
  testWidgets(
    'Free Settings export action, busy, ready save/share; no auto share',
    (tester) async {
      PackageInfo.setMockInitialValues(
        appName: 'Kuktám',
        packageName: 'com.bronxii.kuktam',
        version: '1',
        buildNumber: '1',
        buildSignature: '',
      );
      final s = SessionFixture();
      final p = Port()..wait = Completer<void>();
      final f = Files();
      final c = controller(s, p, f);
      await tester.pumpWidget(
        withFreeAccess(
          MaterialApp(
            home: SettingsScreen(
              authRepository: UiRepo(),
              exportControllerFactory: () => c,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Saját adatok exportálása'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(f.shares, 0);
      p.wait!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Mentés'), findsOneWidget);
      expect(find.text('Megosztás'), findsOneWidget);
      await tester.tap(find.text('Mentés'));
      await tester.pumpAndSettle();
      expect(f.saves, 1);
      expect(find.text('A ZIP mentése befejeződött.'), findsOneWidget);
      expect(find.text('Kuktám Pro funkció'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
