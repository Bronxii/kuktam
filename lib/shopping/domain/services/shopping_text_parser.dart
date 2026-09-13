import '../models/shopping_import_draft.dart';
import '../../../core/domain/services/import_quantity_parser.dart';
import '../../../core/domain/services/import_unit_normalizer.dart';

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
  static const _quantityParser = ImportQuantityParser();
  static const _unitNormalizer = ImportUnitNormalizer();

  double? parseQuantity(String text) {
    return _quantityParser.parse(text);
  }

  String? recognizeUnit(String text) {
    return _unitNormalizer.recognize(text)?.unit;
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
      RegExp(r'^[+-]?\d[\d.,/]*$').hasMatch(token) ||
      const ['½', '¼', '¾'].contains(token) ||
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
        r'^([+-]?\d[\d.,/]*|[½¼¾])([^\d.,/]+\.?)$',
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
    var conversion = const ImportUnitConversion('db', 1);
    var quantityText = '1';
    final missing = quantities.isEmpty;
    final removed = <int>{};
    if (!missing) {
      final position = quantities.single;
      quantityText = tokens[position];
      removed.add(position);
      if (position == 0) {
        if (tokens.length > 1 && recognizeUnit(tokens[1]) != null) {
          conversion = _unitNormalizer.recognize(tokens[1])!;
          unit = conversion.unit;
          removed.add(1);
        }
      } else if (position == tokens.length - 1) {
        // name + quantity
      } else if (position == tokens.length - 2 &&
          recognizeUnit(tokens.last) != null) {
        conversion = _unitNormalizer.recognize(tokens.last)!;
        unit = conversion.unit;
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
        conversion = _unitNormalizer.recognize(tokens.first)!;
        removed.add(0);
      } else if (last != null) {
        unit = last;
        conversion = _unitNormalizer.recognize(tokens.last)!;
        removed.add(tokens.length - 1);
      }
    }
    final name = [
      for (var i = 0; i < tokens.length; i++)
        if (!removed.contains(i)) tokens[i],
    ].join(' ').trim();
    final parsed = parseQuantity(quantityText);
    final normalized = parsed == null
        ? null
        : conversion.normalizeForImport(parsed);
    final quantity = normalized?.quantity;
    if (normalized != null) unit = normalized.unit;
    // Editable text must describe the canonical unit as well. Raw source stays
    // in rawSegment; unchanged decimals retain the user's original spelling.
    if (quantity != null &&
        (conversion.factor != 1 ||
            unit != conversion.unit ||
            quantity != parsed ||
            quantityText.contains('/') ||
            const ['½', '¼', '¾'].contains(quantityText))) {
      quantityText = quantity
          .toString()
          .replaceFirst(RegExp(r'\.0$'), '')
          .replaceAll('.', ',');
    }
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
