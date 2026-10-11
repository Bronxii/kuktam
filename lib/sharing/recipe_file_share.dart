import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../recipes/domain/models/recipe.dart';
import 'recipe_share_codec.dart';

Future<void> shareRecipeFile(
  Recipe recipe, {
  Future<Directory> Function()? tempDirectory,
}) async {
  final bytes = RecipeShareCodec.encode(recipe);
  Directory? dir;
  try {
    final root = Directory(
      '${(await (tempDirectory ?? getTemporaryDirectory)()).path}/kuktam_recipe_shares',
    );
    await root.create(recursive: true);
    dir = await root.createTemp('recipe-');
    final file = File('${dir.path}/${RecipeShareCodec.filename(recipe.name)}');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: RecipeShareCodec.mime)],
        title: 'Megosztás Kuktámmal',
      ),
    );
  } on RecipeShareFailure {
    rethrow;
  } catch (_) {
    throw const RecipeShareFailure('read');
  } finally {
    // Android share_plus owns a separate cache copy for the recipient.
    if (dir != null) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  }
}
