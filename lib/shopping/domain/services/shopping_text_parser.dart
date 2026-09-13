import '../models/shopping_import_draft.dart';
import '../shopping_units.dart';

enum ShoppingTextLimit { characters, items }

class ShoppingTextLimitException implements Exception {
  const ShoppingTextLimitException(this.limit);
  final ShoppingTextLimit limit;
  @override
  String toString() => 'Shopping text exceeds ${limit.name} limit.';
}

/// Conservative, local parsing. No rounding, persistence or UI dependencies.
class ShoppingTextParser {
  const ShoppingTextParser();
  static const maxCharacters = 20000;
  static const maxItems = 200;
  static const _aliases = <String, String>{
    'darab': 'db',
    'gr': 'g',
    'kiló': 'kg',
    'kilo': 'kg',
    'liter': 'l',
    'teáskanál': 'tk',
    'evőkanál': 'ek',
    'csom': 'csomag',
  };

  double? parseQuantity(String text) {
    final trimmed = text.trim();
    if (!RegExp(r'^\d+(?:[.,]\d+)?$').hasMatch(trimmed)) return null;
    final value = double.tryParse(trimmed.replaceAll(',', '.'));
    return value != null && value.isFinite && value > 0 ? value : null;
  }

  String? recognizeUnit(String text) {
    var token = text.trim().toLowerCase();
    if (token.endsWith('.')) token = token.substring(0, token.length - 1);
    return shoppingUnits.contains(token) ? token : _aliases[token];
  }

  /// Throws a typed limit error instead of returning a truncated list.
  /// Character limit counts Unicode code points; raw segments retain spelling.
  List<ShoppingImportDraft> parse(String text) {
    if (text.runes.length > maxCharacters) {
      throw const ShoppingTextLimitException(ShoppingTextLimit.characters);
    }
    final segments = _segments(
      text.replaceAll('\r\n', '\n').replaceAll('\r', '\n'),
    );
    final result = <ShoppingImportDraft>[];
    for (var i = 0; i < segments.length; i++) {
      final draft = _parseSegment(segments[i], i);
      if (draft == null) continue;
      result.add(draft);
      if (result.length > maxItems) {
        throw const ShoppingTextLimitException(ShoppingTextLimit.items);
      }
    }
    return List.unmodifiable(result);
  }

  List<String> _segments(String text) {
    final parts = <String>[];
    var start = 0;
    bool digit(int index) =>
        index >= 0 &&
        index < text.length &&
        text.codeUnitAt(index) >= 48 &&
        text.codeUnitAt(index) <= 57;
    for (var i = 0; i < text.length; i++) {
      if (text[i] == '\n' ||
          text[i] == ';' ||
          (text[i] == ',' && !(digit(i - 1) && digit(i + 1)))) {
        parts.add(text.substring(start, i));
        start = i + 1;
      }
    }
    parts.add(text.substring(start));
    return parts;
  }

  bool _quantityLike(String token) =>
      RegExp(r'^[+-]?\d[\d.,]*$').hasMatch(token) ||
      [
        'nan',
        'infinity',
        '+infinity',
        '-infinity',
      ].contains(token.toLowerCase());

  ShoppingImportDraft? _parseSegment(String raw, int index) {
    var text = raw.trim();
    text = text.replaceFirst(RegExp(r'^(?:•\s*|[-*–](?:\s+|$))'), '');
    text = text.replaceFirst(RegExp(r'^\d+[.)](?:\s+|$)'), '').trim();
    if (!RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(text)) return null;

    // Split attached units only on a complete approved unit token (500g).
    final tokens = <String>[];
    for (final token in text.split(RegExp(r'\s+'))) {
      final attached = RegExp(
        r'^([+-]?\d[\d.,]*)([^\d.,]+\.?)$',
      ).firstMatch(token);
      if (attached != null && recognizeUnit(attached[2]!) != null) {
        tokens.addAll([attached[1]!, attached[2]!]);
      } else {
        tokens.add(token);
      }
    }
    final quantities = [
      for (var i = 0; i < tokens.length; i++)
        if (_quantityLike(tokens[i])) i,
    ];
    ShoppingImportDraft ambiguous() => ShoppingImportDraft(
      rawSegment: raw,
      sourceIndex: index,
      name: text,
      quantityText: '',
      quantity: null,
      unit: 'db',
      quantityWasMissing: false,
      issue: ShoppingImportIssue.ambiguous,
    );
    if (quantities.length > 1) return ambiguous();
    var unit = 'db';
    var quantityText = '1';
    final missing = quantities.isEmpty;
    final removed = <int>{};
    if (!missing) {
      final position = quantities.single;
      quantityText = tokens[position];
      removed.add(position);
      if (position == 0) {
        if (tokens.length > 1 && recognizeUnit(tokens[1]) != null) {
          unit = recognizeUnit(tokens[1])!;
          removed.add(1);
        }
      } else if (position == tokens.length - 1) {
        // name + quantity
      } else if (position == tokens.length - 2 &&
          recognizeUnit(tokens.last) != null) {
        unit = recognizeUnit(tokens.last)!;
        removed.add(tokens.length - 1);
      } else {
        return ambiguous();
      }
    } else {
      final first = recognizeUnit(tokens.first);
      final last = recognizeUnit(tokens.last);
      if (tokens.length > 1 && first != null && last != null) {
        return ambiguous();
      }
      if (first != null) {
        unit = first;
        removed.add(0);
      } else if (last != null) {
        unit = last;
        removed.add(tokens.length - 1);
      }
    }
    final name = [
      for (var i = 0; i < tokens.length; i++)
        if (!removed.contains(i)) tokens[i],
    ].join(' ').trim();
    final quantity = parseQuantity(quantityText);
    return ShoppingImportDraft(
      rawSegment: raw,
      sourceIndex: index,
      name: name,
      quantityText: quantityText,
      quantity: quantity,
      unit: unit,
      quantityWasMissing: missing,
      issue: quantity == null
          ? ShoppingImportIssue.invalidQuantity
          : name.isEmpty
          ? ShoppingImportIssue.missingName
          : null,
    );
  }
}
