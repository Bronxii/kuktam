import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'recipe_export.dart';
import 'recipe_export_formatter.dart';

String exportArchiveName(DateTime time) {
  final t = time.toUtc();
  String n(int v) => v.toString().padLeft(2, '0');
  return 'Kuktam-receptek-${t.year}${n(t.month)}${n(t.day)}-${n(t.hour)}${n(t.minute)}${n(t.second)}Z.zip';
}

/// Runs in an isolate in production; streams ZIP output to disk, not a ZIP byte copy.
void writeRecipeExport({
  required String path,
  required List<ExportRecipe> recipes,
  required DateTime time,
  required String appVersion,
  required String appBuild,
}) {
  final zip = ZipFileEncoder();
  var opened = false;
  try {
    final entries = [
      for (var i = 0; i < recipes.length; i++)
        recipes[i].toJson(
          exportTextFileName(recipes[i].name, i + 1, recipes.length),
        ),
    ];
    final json = const JsonEncoder.withIndent('  ').convert({
      'format': 'kuktam.recipes',
      'exportVersion': 1,
      'exportedAt': time.toUtc().toIso8601String(),
      'appVersion': appVersion,
      'appBuild': appBuild,
      'recipes': entries,
    });
    zip.create(path);
    opened = true;
    void add(String name, String text) {
      final bytes = utf8.encode(text);
      zip.addArchiveFile(ArchiveFile(name, bytes.length, bytes));
    }

    add('recipes.json', '$json\n');
    add(
      'export_info.txt',
      'Kuktám recept-export\nFormátumverzió: 1\nUTC: ${time.toUtc().toIso8601String()}\n'
          'Receptek száma: ${recipes.length}\nCsak receptek; shopping és fiókadatok nélkül.\n'
          'A recipes.json a későbbi gépi visszaállítás alapja. Restore jelenleg nincs az appban.\n',
    );
    for (var i = 0; i < recipes.length; i++) {
      add(entries[i]['textFile']! as String, exportRecipeText(recipes[i]));
    }
    zip.closeSync();
    opened = false;
  } catch (_) {
    if (opened) {
      try {
        zip.closeSync();
      } catch (_) {}
    }
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
    throw const ExportFailure('build');
  }
}
