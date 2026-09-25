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
  unresolvedQuantityExpression,
  unverifiedSource,
  missingQuantity,
  invalidIngredient,
}

enum WebImportSeverity { blocking, review, info }

enum WebImportIssueOrigin { source, parser, webAudit, normalization, structure }

class WebImportIssue {
  const WebImportIssue(
    this.code,
    this.severity, {
    this.row,
    this.detail,
    this.rowId,
    this.origin = WebImportIssueOrigin.structure,
    this.evidence,
    this.field,
  });
  final WebImportIssueCode code;
  final WebImportSeverity severity;
  final int? row;
  final String? rowId;
  final WebImportIssueOrigin origin;
  final String? evidence;
  final String? field;
  String get messageKey => 'webImport.${code.name}';
  String get identity => '${code.name}:${field ?? ''}:${origin.name}';

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
