enum WebImportIssueCode {
  invalidUrl,
  unsafeTarget,
  cancelled,
  timeout,
  fetchError,
  httpError,
  accessBlocked,
  rateLimited,
  tooLarge,
  invalidContentType,
  invalidEncoding,
  tooManyRedirects,
  noRecipe,
  invalidRecipe,
  multipleRecipes,
  missingTitle,
  missingIngredients,
  missingPreparation,
  unknownDomain,
  knownSourceRisk,
  sourceStructureWarning,
  invalidQuantity,
  unknownUnit,
  unsupportedUnit,
  ambiguousIngredient,
  silentDbFallbackRisk,
}

enum WebImportSeverity { blocking, review }

class WebImportIssue {
  const WebImportIssue(this.code, this.severity, {this.row, this.detail});
  final WebImportIssueCode code;
  final WebImportSeverity severity;
  final int? row;

  /// Internal diagnostic only. Never display raw network exception text.
  final String? detail;
}

class WebImportFailure implements Exception {
  const WebImportFailure(this.code, {this.httpStatus});
  final WebImportIssueCode code;
  final int? httpStatus;
  WebImportIssue get issue => WebImportIssue(code, WebImportSeverity.blocking);
  @override
  String toString() => 'WebImportFailure(${code.name})';
}
