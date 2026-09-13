/// Parses a quantity token only, never prose. Null means invalid, not zero.
class ImportQuantityParser {
  const ImportQuantityParser();

  double? parse(String input) {
    final text = input.trim();
    double? value;
    const fractions = {'½': 0.5, '¼': 0.25, '¾': 0.75};
    if (fractions.containsKey(text)) {
      value = fractions[text];
    } else if (RegExp(r'^\d+/\d+$').hasMatch(text)) {
      final parts = text.split('/');
      final numerator = double.tryParse(parts[0]);
      final denominator = double.tryParse(parts[1]);
      if (numerator == null ||
          !numerator.isFinite ||
          denominator == null ||
          !denominator.isFinite ||
          denominator <= 0) {
        return null;
      }
      value = numerator / denominator;
    } else if (RegExp(r'^\d+(?:[.,]\d+)?$').hasMatch(text)) {
      value = double.tryParse(text.replaceAll(',', '.'));
    }
    return value != null && value.isFinite && value > 0 ? value : null;
  }
}
