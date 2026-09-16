/// Hungarian alphabet ordering for recipe display, never for name uniqueness.
/// Case and surrounding whitespace are ignored in the primary comparison.
/// Original spelling breaks ties; repositories may then break exact ties by ID.
int compareHungarianRecipeNames(String a, String b) {
  final left = _letters(a.trim().toLowerCase());
  final right = _letters(b.trim().toLowerCase());
  for (var i = 0; i < left.length && i < right.length; i++) {
    final comparison = left[i].compareTo(right[i]);
    if (comparison != 0) return comparison;
  }
  final lengthComparison = left.length.compareTo(right.length);
  return lengthComparison != 0 ? lengthComparison : a.compareTo(b);
}

const _alphabet = [
  'a',
  'á',
  'b',
  'c',
  'cs',
  'd',
  'dz',
  'dzs',
  'e',
  'é',
  'f',
  'g',
  'gy',
  'h',
  'i',
  'í',
  'j',
  'k',
  'l',
  'ly',
  'm',
  'n',
  'ny',
  'o',
  'ó',
  'ö',
  'ő',
  'p',
  'q',
  'r',
  's',
  'sz',
  't',
  'ty',
  'u',
  'ú',
  'ü',
  'ű',
  'v',
  'w',
  'x',
  'y',
  'z',
  'zs',
];

List<int> _letters(String text) {
  final characters = text.runes.map(String.fromCharCode).toList();
  final result = <int>[];
  for (var i = 0; i < characters.length;) {
    var matched = false;
    // Longest match first: dzs is one letter, not dz followed by s.
    for (var length = 3; length >= 1; length--) {
      if (i + length > characters.length) continue;
      final index = _alphabet.indexOf(characters.sublist(i, i + length).join());
      if (index < 0) continue;
      result.add(100 + index);
      i += length;
      matched = true;
      break;
    }
    if (!matched) {
      final rune = characters[i++].runes.single;
      // Spaces, digits and ASCII punctuation precede letters; other characters
      // have a deterministic Unicode fallback after the Hungarian alphabet.
      result.add(rune < 97 ? rune : 1000 + rune);
    }
  }
  return result;
}
