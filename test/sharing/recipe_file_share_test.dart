import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/sharing/recipe_file_share.dart';
import 'package:kuktam/sharing/recipe_share_codec.dart';
import 'recipe_share_codec_test.dart' show sampleRecipe;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'real outbound file is UTF8 allowlist, correct MIME, readable during handoff',
    () async {
      final root = await Directory.systemTemp.createTemp('k2k-test-');
      addTearDown(() => root.delete(recursive: true));
      const channel = MethodChannel('dev.fluttercommunity.plus/share');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      String? sharedPath;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'share');
        expect(call.arguments['mimeTypes'], [RecipeShareCodec.mime]);
        sharedPath = (call.arguments['paths'] as List).single as String;
        expect(sharedPath, endsWith('.kuktamrecipe'));
        final bytes = await File(sharedPath!).readAsBytes();
        expect(RecipeShareCodec.decode(bytes).toMap(), sampleRecipe.toMap());
        expect(utf8.decode(bytes), isNot(contains('PRIVATE_DOC')));
        return 'target';
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await shareRecipeFile(sampleRecipe, tempDirectory: () async => root);
      expect(sharedPath, isNotNull);
      expect(await File(sharedPath!).exists(), isFalse);
    },
  );
}
