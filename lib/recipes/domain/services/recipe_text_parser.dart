import '../../../core/domain/measurement_units.dart';
import '../../../core/domain/services/import_quantity_parser.dart';
import '../../../core/domain/services/import_unit_normalizer.dart';
import '../models/recipe_import_draft.dart';

/// Conservative line/section recognition. All numeric rules belong to P1.
class RecipeTextParser {
  const RecipeTextParser();

  static const _quantities = ImportQuantityParser();
  static const _units = ImportUnitNormalizer();
  static const _unknownUnits = {'bögre', 'pohár', 'csipet', 'marék'};
  static const _footer = 'Készült a Kuktám alkalmazással';

  RecipeImportDraft parse(String text) {
    final lines = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    final normalized = lines.map(_normalizeLine).toList();
    final webMeta = _webMetaLines(normalized);
    final ingredients = <RecipeImportIngredientDraft>[];
    final unprocessed = <String>[];
    var end = lines.length;
    while (end > 0 && lines[end - 1].trim().isEmpty) {
      end--;
    }
    // Only the exact trailing export signature is removed from preparation.
    var footerStart = end;
    if (end > 0 && lines[end - 1].trim() == _footer) {
      footerStart = end - 1;
      while (footerStart > 0 && lines[footerStart - 1].trim().isEmpty) {
        footerStart--;
      }
      if (footerStart > 0 &&
          RegExp(r'^─+$').hasMatch(lines[footerStart - 1].trim())) {
        footerStart--;
      }
    }

    final firstSection = normalized
        .take(footerStart)
        .toList()
        .indexWhere((line) => _section(line) != null);
    var titleIndex = -1;
    if (firstSection >= 0 &&
        _section(normalized[firstSection]) == _Section.ingredients) {
      final candidates = <int>[
        for (var i = 0; i < firstSection; i++)
          if (!_structural(normalized[i]) &&
              !_isMeta(normalized[i]) &&
              !webMeta.contains(i) &&
              !_wholeLink(lines[i]) &&
              !_numericValue(normalized[i]))
            i,
      ];
      if (candidates.length == 1) {
        final i = candidates.single;
        final tokens = _tokens(_clean(normalized[i]));
        if (RegExp(r'\p{L}', unicode: true).hasMatch(normalized[i]) &&
            !tokens.any(_quantityLike) &&
            !_hasListPrefix(normalized[i]) &&
            !RegExp(r'[.!?:]$').hasMatch(normalized[i])) {
          titleIndex = i;
        }
      }
    }

    var inIngredients = false;
    var preparation = '';
    for (var i = 0; i < footerStart; i++) {
      final raw = lines[i];
      final line = normalized[i];
      if (i == titleIndex || _structural(line)) continue;
      final section = _section(line);
      if (section == _Section.preparation) {
        var preparationEnd = footerStart;
        for (var j = i + 1; j < footerStart; j++) {
          if (_infoHeading(normalized[j])) {
            final next = _nextContent(normalized, j + 1);
            if (next < footerStart && _isMeta(_clean(normalized[next]))) {
              preparationEnd = j;
              break;
            }
          }
        }
        preparation = lines.sublist(i + 1, preparationEnd).join('\n').trim();
        unprocessed.addAll(
          lines
              .sublist(preparationEnd, footerStart)
              .where((line) => !_structural(_normalizeLine(line))),
        );
        break;
      }
      if (section == _Section.ingredients) {
        inIngredients = true;
        continue;
      }
      if (_isMeta(line) ||
          webMeta.contains(i) ||
          (i < firstSection && (_wholeLink(raw) || _numericValue(line)))) {
        unprocessed.add(raw);
        continue;
      }
      final clean = _clean(line);
      if (clean.isEmpty) {
        unprocessed.add(raw);
        continue;
      }
      if (inIngredients || _isStructuredIngredient(clean)) {
        ingredients.add(_ingredient(raw, clean, i));
      } else {
        unprocessed.add(raw);
      }
    }
    unprocessed.addAll(lines.sublist(footerStart, end));
    return RecipeImportDraft(
      originalText: text,
      title: titleIndex < 0 ? '' : normalized[titleIndex],
      ingredients: ingredients,
      preparationText: preparation,
      unprocessedSegments: unprocessed,
    );
  }

  // Recognition view only: raw lines and preparation retain their source text.
  String _normalizeLine(String line) => line
      .trim()
      .replaceFirst(RegExp(r'^#{1,6}(?!#)\s*'), '')
      .replaceAllMapped(
        RegExp(r'\[([^\[\]\n]*)\]\([^()\s]*\)'),
        (match) => match[1]!,
      )
      .trim();

  bool _wholeLink(String line) =>
      RegExp(r'^\s*\[[^\[\]\n]+\]\([^()\s]*\)\s*$').hasMatch(line);

  bool _structural(String line) =>
      line.isEmpty || RegExp(r'^[\s*#•–_\-]+$').hasMatch(line);

  bool _numericValue(String line) => RegExp(
    r'^\d+(?:[.,]\d+)?\s*(?:g|mg|µg|kcal|kj|%)?$',
    caseSensitive: false,
  ).hasMatch(line);

  int _nextContent(List<String> lines, int start) {
    while (start < lines.length && _structural(lines[start])) {
      start++;
    }
    return start;
  }

  bool _infoHeading(String line) => const {
    'recept infó',
    'receptinformáció',
    'recipe info',
    'információk',
  }.contains(line.toLowerCase().replaceFirst(RegExp(r':$'), '').trim());

  Set<int> _webMetaLines(List<String> lines) {
    final result = <int>{};
    const labels = {
      'kalória',
      'kcal',
      'fehérje',
      'protein',
      'szénhidrát',
      'zsír',
      'víz',
      'koleszterin',
      'élelmi rost',
      'rost',
      'cukor',
      'só',
      'nátrium',
    };
    // A run needs multiple labels AND values. Bare ingredient names never
    // establish nutrition context, nor does "100 g cukor" match a value.
    for (var start = 0; start < lines.length;) {
      var end = start;
      var labelCount = 0;
      var valueCount = 0;
      while (end < lines.length) {
        final line = lines[end];
        if (labels.contains(line.toLowerCase())) {
          labelCount++;
        } else if (_numericValue(line)) {
          valueCount++;
        } else if (!_structural(line)) {
          break;
        }
        end++;
      }
      if (labelCount >= 2 && valueCount >= 2) {
        result.addAll(
          Iterable.generate(end - start, (offset) => start + offset),
        );
      }
      start = end > start ? end : start + 1;
    }
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].toLowerCase();
      if (const {'hirdetés', 'advertisement', 'ad'}.contains(line) ||
          RegExp(
            r'^(?:\d+\s*)?(?:értékelés|hozzászólás)(?:\s*•\s*(?:\d+\s*)?(?:értékelés|hozzászólás))*$',
          ).hasMatch(line) ||
          RegExp(r'^állítsd be itt(?:\s|,)').hasMatch(line) ||
          line.replaceAll('*', '').trim() == 'adag') {
        result.add(i);
      }
      if (!const {'idő', 'költség', 'nehézség', 'adag'}.contains(line)) {
        continue;
      }
      result.add(i);
      final next = _nextContent(lines, i + 1);
      if (next == lines.length) continue;
      final value = lines[next].toLowerCase();
      final matches = switch (line) {
        'idő' => RegExp(
          r'^\d+(?:[.,]\d+)?\s*(?:p|perc|óra|h|min)\.?$',
        ).hasMatch(value),
        'költség' => const {
          'megfizethető',
          'olcsó',
          'közepes',
          'drága',
        }.contains(value),
        'nehézség' => const {
          'könnyű',
          'egyszerű',
          'közepes',
          'nehéz',
        }.contains(value),
        _ => _isMeta(value) || _numericValue(value),
      };
      if (matches) result.add(next);
    }
    return result;
  }

  _Section? _section(String line) {
    final heading = line
        .trim()
        .toLowerCase()
        .replaceFirst(RegExp(r':$'), '')
        .trim();
    return switch (heading) {
      'hozzávalók' || 'fűszerek' => _Section.ingredients,
      'elkészítés' || 'elkészítés menete' => _Section.preparation,
      _ => null,
    };
  }

  bool _isMeta(String line) {
    final text = line.trim();
    return RegExp(
          r'^(?:idő|elkészítési idő|sütési idő|főzési idő|pihentetési idő|előkészítés ideje|sütés ideje|teljes idő|adag|kalória|kcal)\s*:',
          caseSensitive: false,
        ).hasMatch(text) ||
        RegExp(
          // Whole-line amounts/ranges only: "4 adag liszt" is not metadata.
          r'^(?:kb\.?\s*)?\d+(?:[.,]\d+)?(?:\s*[-–]\s*\d+(?:[.,]\d+)?)?\s*(?:adag|fő|kcal)\.?$',
          caseSensitive: false,
        ).hasMatch(text);
  }

  bool _hasListPrefix(String line) =>
      RegExp(r'^(?:[•*–-]\s|\d+[.)]\s)').hasMatch(line.trim());

  String _clean(String line) => line
      .trim()
      .replaceFirst(RegExp(r'^(?:•\s*|[-*–](?:\s+|$))'), '')
      .replaceFirst(RegExp(r'^\d+[.)](?:\s+|$)'), '')
      .trim();

  // Lexical candidates only: validity and numeric conversion use P1.parse.
  bool _quantityLike(String token) =>
      RegExp(r'^[+-]?\d[\d.,/]*$').hasMatch(token) ||
      const [
        '½',
        '¼',
        '¾',
        'nan',
        'infinity',
        '+infinity',
        '-infinity',
      ].contains(token.toLowerCase());

  bool _unknown(String token) => _unknownUnits.contains(
    token.toLowerCase().replaceFirst(RegExp(r'\.$'), ''),
  );

  List<String> _tokens(String line) {
    final result = <String>[];
    for (final token in line.split(RegExp(r'\s+'))) {
      final attached = RegExp(
        r'^([+-]?\d[\d.,/]*|[½¼¾])([^\d.,/]+)$',
      ).firstMatch(token);
      if (attached != null && _units.recognize(attached[2]!) != null) {
        result.addAll([attached[1]!, attached[2]!]);
      } else {
        result.add(token);
      }
    }
    return result;
  }

  bool _isStructuredIngredient(String line) {
    final tokens = _tokens(line);
    if (!RegExp(r'\p{L}', unicode: true).hasMatch(line)) return false;
    final positions = [
      for (var i = 0; i < tokens.length; i++)
        if (_quantityLike(tokens[i])) i,
    ];
    if (positions.length != 1) return false;
    final position = positions.single;
    final nameTokens = tokens.where(
      (t) => !_quantityLike(t) && _units.recognize(t) == null,
    );
    // Sentence punctuation is not evidence of an ingredient without a section.
    if (nameTokens.any((t) => RegExp(r'[.!?:;]').hasMatch(t))) return false;
    return position == 0 ||
        position == tokens.length - 1 ||
        (position == tokens.length - 2 &&
            (_units.recognize(tokens.last) != null || _unknown(tokens.last)));
  }

  RecipeImportIngredientDraft _ingredient(String raw, String clean, int order) {
    final tokens = _tokens(clean);
    final positions = [
      for (var i = 0; i < tokens.length; i++)
        if (_quantityLike(tokens[i])) i,
    ];
    RecipeImportIngredientDraft ambiguous() => RecipeImportIngredientDraft(
      sourceOrder: order,
      rawText: raw,
      name: clean,
      quantity: null,
      rawQuantityText: null,
      unit: MeasurementUnits.db,
      warnings: [RecipeImportWarning.ambiguousIngredient],
    );
    if (positions.length > 1) return ambiguous();
    if (positions.isEmpty) {
      return RecipeImportIngredientDraft(
        sourceOrder: order,
        rawText: raw,
        name: clean,
        quantity: 1,
        rawQuantityText: null,
        unit: MeasurementUnits.db,
        warnings: [RecipeImportWarning.missingQuantity],
      );
    }
    final position = positions.single;
    final removed = <int>{position};
    int? unitIndex;
    if (position == 0) {
      if (tokens.length > 1) unitIndex = 1;
    } else if (position == tokens.length - 2 &&
        (_units.recognize(tokens.last) != null || _unknown(tokens.last))) {
      unitIndex = tokens.length - 1;
    } else if (position != tokens.length - 1) {
      return ambiguous();
    }
    var conversion = const ImportUnitConversion(MeasurementUnits.db, 1);
    final warnings = <RecipeImportWarning>[];
    if (unitIndex != null) {
      final known = _units.recognize(tokens[unitIndex]);
      if (known != null) {
        conversion = known;
        removed.add(unitIndex);
      } else if (_unknown(tokens[unitIndex])) {
        warnings.add(RecipeImportWarning.unknownUnit);
        removed.add(unitIndex);
      }
    }
    // Kuktám export delimiter, only immediately before a suffix quantity.
    if (position > 0 && tokens[position - 1] == '–') removed.add(position - 1);
    final name = [
      for (var i = 0; i < tokens.length; i++)
        if (!removed.contains(i)) tokens[i],
    ].join(' ').trim();
    if (name.isEmpty || !RegExp(r'\p{L}', unicode: true).hasMatch(name)) {
      return ambiguous();
    }
    final parsed = _quantities.parse(tokens[position]);
    final normalized = parsed == null
        ? null
        : conversion.normalizeForImport(parsed);
    if (normalized == null) warnings.add(RecipeImportWarning.invalidQuantity);
    return RecipeImportIngredientDraft(
      sourceOrder: order,
      rawText: raw,
      name: name,
      quantity: normalized?.quantity,
      rawQuantityText: tokens[position],
      unit: normalized?.unit ?? conversion.unit,
      warnings: warnings,
    );
  }
}

enum _Section { ingredients, preparation }
