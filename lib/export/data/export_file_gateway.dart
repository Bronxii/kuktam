import 'dart:io';
import 'dart:isolate';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../domain/recipe_export.dart';
import '../domain/recipe_export_encoder.dart';

class ExportArtifact {
  const ExportArtifact(this.path, this.name, this.count);
  final String path, name;
  final int count;
}

abstract interface class ExportFileGateway {
  Future<ExportArtifact> build(
    List<ExportRecipe> recipes,
    DateTime time,
    String version,
    String build,
  );
  Future<bool> save(ExportArtifact artifact, void Function() check);
  Future<void> share(ExportArtifact artifact, void Function() check);
  Future<void> discard(ExportArtifact artifact);
  Future<void> cancel();
}

class AndroidExportFileGateway implements ExportFileGateway {
  static const _channel = MethodChannel('kuktam/export_document');
  @override
  Future<ExportArtifact> build(
    List<ExportRecipe> recipes,
    DateTime time,
    String version,
    String build,
  ) async {
    final root = Directory(
      '${(await getTemporaryDirectory()).path}/kuktam_exports',
    );
    await root.create(recursive: true);
    final dir = await root.createTemp('export-');
    final name = exportArchiveName(time);
    final path = '${dir.path}/$name';
    try {
      await Isolate.run(
        () => writeRecipeExport(
          path: path,
          recipes: recipes,
          time: time,
          appVersion: version,
          appBuild: build,
        ),
      );
      return ExportArtifact(path, name, recipes.length);
    } catch (_) {
      await dir.delete(recursive: true);
      rethrow;
    }
  }

  @override
  Future<bool> save(ExportArtifact artifact, void Function() check) async {
    check();
    final selected = await _channel.invokeMethod<bool>('choose', {
      'title': artifact.name,
    });
    try {
      check();
      if (selected != true) return false;
      final done = await _channel.invokeMethod<bool>('write', {
        'path': artifact.path,
      });
      check();
      if (done != true) throw const ExportFailure('save');
      return true;
    } finally {
      await cancel();
    }
  }

  @override
  Future<void> share(ExportArtifact artifact, void Function() check) async {
    check();
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(artifact.path, mimeType: 'application/zip')],
        title: 'Kuktám recept-export',
      ),
    );
    check(); // A share-sheet handoff is not a verified external save.
  }

  @override
  Future<void> cancel() async {
    try {
      await _channel.invokeMethod<void>('cancel');
    } on PlatformException {
      /* No content logged. */
    }
  }

  @override
  Future<void> discard(ExportArtifact artifact) async {
    final file = File(artifact.path);
    // Only a path produced by build, scoped to our own export folder.
    final root = Directory(
      '${(await getTemporaryDirectory()).path}/kuktam_exports',
    ).absolute.path;
    final parent = file.absolute.parent;
    if (parent.parent.path != root ||
        !parent.uri.pathSegments
            .where((p) => p.isNotEmpty)
            .last
            .startsWith('export-')) {
      return;
    }
    if (await parent.exists()) await parent.delete(recursive: true);
  }
}
