import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/core/domain/services/import_quantity_parser.dart';

void main() {
  const parser = ImportQuantityParser();
  for (final entry in {
    '1': 1.0,
    '1.5': 1.5,
    '1,5': 1.5,
    ' 1,5 ': 1.5,
    '1/2': 0.5,
    '1/4': 0.25,
    '3/4': 0.75,
    '½': 0.5,
    '¼': 0.25,
    '¾': 0.75,
    '1,234': 1.234,
  }.entries) {
    test('parses ${entry.key} without rounding', () {
      expect(parser.parse(entry.key), entry.value);
    });
  }
  test('invalid tokens never become zero or a default', () {
    for (final value in [
      '',
      ' ',
      'abc',
      '0',
      '-1',
      'NaN',
      'Infinity',
      '1/0',
      '0/2',
      '1,2.3',
      'B12',
      '1e3',
      '1 1/2',
      '1 / 2',
      '1${'0' * 400}',
      '1/1${'0' * 400}',
      '0.${'0' * 400}1',
    ]) {
      expect(parser.parse(value), isNull, reason: value);
    }
  });
}
