Object? _freeze(Object? value) {
  // Preserve the established POC API's typed ingredient/instruction lists.
  if (value is List<String>) return List<String>.unmodifiable(value);
  if (value is List<Map<String, String>>) {
    return List<Map<String, String>>.unmodifiable(
      value.map((v) => Map<String, String>.unmodifiable(v)),
    );
  }
  if (value is Map) {
    return Map<String, Object?>.unmodifiable(
      value.map((k, v) => MapEntry(k as String, _freeze(v))),
    );
  }
  if (value is List) return List<Object?>.unmodifiable(value.map(_freeze));
  return value;
}

/// Immutable snapshot of one JSON-LD candidate, including raw evidence.
class WebRecipeCandidate {
  WebRecipeCandidate(Map<String, Object?> data)
    : data = _freeze(data) as Map<String, Object?>;
  final Map<String, Object?> data;
  String? get title => data['title'] as String?;
  bool get valid => data['valid'] == true;
  List<String> get ingredients =>
      List.unmodifiable((data['ingredients'] as List).cast<String>());
  String get preparation => data['preparation'] as String;
}
