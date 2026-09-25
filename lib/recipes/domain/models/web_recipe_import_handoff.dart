import 'recipe_import_draft.dart';
import '../services/web_recipe_import_service.dart';
import '../services/web_import_domain_policy.dart';

/// Backward-compatible route result; ephemeral review data never enters Recipe.
class WebRecipeImportHandoff extends RecipeImportDraft {
  factory WebRecipeImportHandoff({
    required WebRecipeImportResult result,
    required String originalUrl,
    required Uri finalUrl,
  }) {
    if (!result.quality.allowsHandoff ||
        result.draft == null ||
        result.review == null) {
      throw ArgumentError('Web result cannot be handed off');
    }
    return WebRecipeImportHandoff._(
      result,
      originalUrl,
      finalUrl,
      result.draft!,
    );
  }
  WebRecipeImportHandoff._(
    this.result,
    this.originalUrl,
    this.finalUrl,
    RecipeImportDraft draft,
  ) : super(
        originalText: draft.originalText,
        title: draft.title,
        ingredients: draft.ingredients,
        preparationText: draft.preparationText,
        unprocessedSegments: draft.unprocessedSegments,
      );
  final WebRecipeImportResult result;
  final String originalUrl;
  final Uri finalUrl;
  WebImportSourceMetadata get source =>
      const WebImportDomainPolicy().identify(finalUrl);
}
