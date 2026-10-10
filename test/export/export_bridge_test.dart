import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/export/data/export_file_gateway.dart';
import 'package:kuktam/export/domain/recipe_export.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('kuktam/export_document');
  const artifact = ExportArtifact(
    '/private/file.zip',
    'Kuktam-receptek-20261010-120000Z.zip',
    1,
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  for (final scenario in [
    'success',
    'cancel',
    'missing-uri',
    'write-failed',
    'busy',
    'session',
  ]) {
    test('SAF bridge $scenario: success only after completed write', () async {
      final calls = <String>[];
      bool invalid = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'choose') {
          expect(call.arguments, {'title': artifact.name});
          if (scenario == 'cancel') return false;
          if (scenario == 'missing-uri' || scenario == 'busy') {
            throw PlatformException(code: scenario);
          }
          if (scenario == 'session') invalid = true;
          return true;
        }
        if (call.method == 'write') {
          expect(call.arguments, {'path': artifact.path});
          if (scenario == 'write-failed') {
            throw PlatformException(code: scenario);
          }
          return true;
        }
        return null;
      });
      final future = AndroidExportFileGateway().save(artifact, () {
        if (invalid) throw const ExportFailure('session');
      });
      if (scenario == 'success' || scenario == 'cancel') {
        expect(await future, scenario == 'success');
      } else {
        await expectLater(future, throwsA(anything));
      }
      expect(
        calls.contains('write'),
        scenario == 'success' || scenario == 'write-failed',
      );
    });
  }
  test('SAF waits for destination copy completion', () async {
    final copy = Completer<bool>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'choose') return true;
      if (call.method == 'write') return copy.future;
      return null;
    });
    bool complete = false;
    final future = AndroidExportFileGateway().save(artifact, () {}).then((
      value,
    ) {
      complete = true;
      return value;
    });
    await Future<void>.delayed(Duration.zero);
    expect(complete, isFalse);
    copy.complete(true);
    expect(await future, isTrue);
  });
  test('outbound share uses ZIP XFile without content/body logging', () async {
    const share = MethodChannel('dev.fluttercommunity.plus/share');
    int calls = 0;
    messenger.setMockMethodCallHandler(share, (call) async {
      calls++;
      expect(call.method, 'share');
      expect(call.arguments['paths'], [artifact.path]);
      expect(call.arguments['mimeTypes'], ['application/zip']);
      expect(call.arguments.containsKey('text'), isFalse);
      return 'dev.fluttercommunity.plus/share/dismissed';
    });
    addTearDown(() => messenger.setMockMethodCallHandler(share, null));
    await AndroidExportFileGateway().share(artifact, () {});
    expect(calls, 1);
  });
}
