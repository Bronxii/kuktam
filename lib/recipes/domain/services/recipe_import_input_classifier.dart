enum RecipeImportInputKind { text, web }

/// Syntactic routing only; security checks must still precede every fetch.
class RecipeImportInputClassifier {
  const RecipeImportInputClassifier();
  RecipeImportInputKind classify(String input) => url(input) == null
      ? RecipeImportInputKind.text
      : RecipeImportInputKind.web;
  Uri? url(String input) {
    final value = input.trim();
    if (value.isEmpty ||
        RegExp(r'[\s\x00-\x1f\x7f\\]').hasMatch(value) ||
        RegExp(r'%(?![0-9a-fA-F]{2})').hasMatch(value)) {
      return null;
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        !uri.hasAuthority ||
        uri.host.isEmpty) {
      return null;
    }
    try {
      uri.port;
    } on FormatException {
      return null;
    }
    return uri;
  }
}
