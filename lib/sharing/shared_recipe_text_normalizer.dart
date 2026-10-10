import '../core/domain/services/import_quantity_parser.dart';
import '../core/domain/services/import_unit_normalizer.dart';

/// Reassembles only unambiguous quantity / known unit / name triples.
/// Shared-text presentation only: no conversion, recipe parsing or logging.
class SharedRecipeTextNormalizer {
  const SharedRecipeTextNormalizer();
  static const _quantities = ImportQuantityParser();
  static const _units = ImportUnitNormalizer();

  String normalize(String text) {
    final newline = text.contains('\r\n')
        ? '\r\n'
        : text.contains('\r')
        ? '\r'
        : '\n';
    final lines = text.split(RegExp(r'\r\n|\r|\n'));
    final output = <String>[];
    var changed = false;
    var preparation = false;
    for (var i = 0; i < lines.length; i++) {
      final quantity = lines[i].trim();
      final heading = quantity
          .toLowerCase()
          .replaceFirst(RegExp(r':$'), '')
          .trim();
      if (heading == 'elkészítés' || heading == 'elkészítés menete') {
        preparation = true;
      }
      if (!preparation && _quantities.parse(quantity) != null) {
        final unitIndex = _nextContent(lines, i + 1);
        if (unitIndex < lines.length &&
            _units.recognize(lines[unitIndex]) != null) {
          final nameIndex = _nextContent(lines, unitIndex + 1);
          if (nameIndex < lines.length && _isName(lines[nameIndex].trim())) {
            output.add(
              '$quantity ${lines[unitIndex].trim()} ${lines[nameIndex].trim()}',
            );
            i = nameIndex;
            changed = true;
            continue;
          }
        }
      }
      output.add(lines[i]);
    }
    // Already-normal and ambiguous payloads are byte-for-byte unchanged.
    return changed ? output.join(newline) : text;
  }

  int _nextContent(List<String> lines, int index) {
    while (index < lines.length && lines[index].trim().isEmpty) {
      index++;
    }
    return index;
  }

  bool _isName(String line) {
    if (!RegExp(r'^\p{L}', unicode: true).hasMatch(line) ||
        RegExp(r'[:.!?\d]').hasMatch(line) ||
        _units.recognize(line) != null) {
      return false;
    }
    return !const {
      'hozzávalók',
      'fűszerek',
      'elkészítés',
      'elkészítés menete',
    }.contains(line.toLowerCase());
  }
}
