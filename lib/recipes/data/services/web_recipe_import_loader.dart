import '../../domain/models/web_recipe_import_handoff.dart';
import '../../domain/models/web_import_issue.dart';
import '../../domain/services/recipe_json_ld_extractor.dart';
import '../../domain/services/web_recipe_import_service.dart';
import 'web_recipe_fetcher.dart';

/// Cancellable network orchestration; deterministic processing stays in domain.
class WebRecipeImportLoader {
  WebRecipeImportLoader({
    WebRecipeFetcher? fetcher,
    this.service = const WebRecipeImportService(),
  }) : fetcher = fetcher ?? WebRecipeFetcher();
  final WebRecipeFetcher fetcher;
  final WebRecipeImportService service;
  Future<WebRecipeImportHandoff> load(
    String input, {
    required WebImportCancellation cancellation,
    required String importId,
  }) async {
    try {
      return await _load(input, cancellation: cancellation, importId: importId);
    } on WebImportFailure {
      rethrow;
    } catch (_) {
      cancellation.check();
      throw const WebImportFailure(WebImportIssueCode.internalFailure);
    }
  }

  Future<WebRecipeImportHandoff> _load(
    String input, {
    required WebImportCancellation cancellation,
    required String importId,
  }) async {
    cancellation.check();
    final fetched = await fetcher.fetch(input, cancellation: cancellation);
    cancellation.check();
    final extraction = extractRecipes(fetched.html);
    cancellation.check();
    final extractionFailure = switch (extraction.status) {
      Status.noJsonLd => WebImportIssueCode.noJsonLd,
      Status.invalidJsonLd => WebImportIssueCode.invalidJsonLd,
      Status.noRecipe => WebImportIssueCode.noRecipe,
      _ => null,
    };
    if (extractionFailure != null) throw WebImportFailure(extractionFailure);
    final result = service.prepare(
      extraction,
      sourceUrl: fetched.finalUrl,
      importId: importId,
    );
    cancellation.check();
    if (!result.quality.allowsHandoff ||
        result.draft == null ||
        result.review == null) {
      // Multiple-candidate explanation takes precedence over generic invalid data.
      final codes = result.quality.issues.map((i) => i.code);
      throw WebImportFailure(
        codes.contains(WebImportIssueCode.multipleRecipes)
            ? WebImportIssueCode.multipleRecipes
            : WebImportIssueCode.invalidRecipe,
      );
    }
    return WebRecipeImportHandoff(
      result: result,
      originalUrl: fetched.originalUrl,
      finalUrl: fetched.finalUrl,
    );
  }
}
