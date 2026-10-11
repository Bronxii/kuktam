import 'dart:convert';
import 'recipe_export.dart';

String safeRecipeFileName(String name) {
  var safe = name
      .replaceAll(
        RegExp(
          r'[/\\:*?"<>|\x00-\x1f\x7f-\x9f\u061c\u200e\u200f\u202a-\u202e\u2066-\u2069]',
        ),
        '_',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'[. ]+$'), '');
  final result = StringBuffer();
  var bytes = 0;
  for (final rune in safe.runes) {
    final char = String.fromCharCode(rune);
    final length = utf8.encode(char).length;
    if (bytes + length > 120) break;
    result.write(char);
    bytes += length;
  }
  safe = result.toString().replaceAll(RegExp(r'[. ]+$'), '');
  if (safe.isEmpty) safe = 'Recept';
  return safe;
}

String exportTextFileName(String name, int index, int count) {
  final safe = safeRecipeFileName(name);
  final width = count.toString().length < 6 ? 6 : count.toString().length;
  return 'receptek/${index.toString().padLeft(width, '0')}-$safe.txt';
}

String exportRecipeText(ExportRecipe recipe) {
  final b = StringBuffer()
    ..writeln(recipe.name)
    ..writeln()
    ..writeln('Hozzávalók:');
  for (final i in recipe.ingredients) {
    b.writeln('• ${i.name} – ${i.formattedQuantity} ${i.unit}');
  }
  if (recipe.spices.isNotEmpty) {
    b.writeln();
    b.writeln('Fűszerek:');
    for (final s in recipe.spices) {
      b.writeln('• ${s.name}');
    }
  }
  if (recipe.preparation.isNotEmpty) {
    b.writeln();
    b.writeln('Elkészítés:');
    b.writeln(recipe.preparation);
  }
  b.writeln();
  b.writeln('──────────────');
  b.writeln('Készült a Kuktám alkalmazással');
  return b.toString();
}
