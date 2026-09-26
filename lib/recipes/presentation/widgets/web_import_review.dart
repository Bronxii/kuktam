import 'package:flutter/material.dart';
import '../../domain/models/web_import_issue.dart';
import '../../domain/models/recipe_import_review_metadata.dart';

String webReviewMessage(WebImportIssueCode code) => switch (code) {
  WebImportIssueCode.invalidQuantity =>
    'A mennyiség hibás. Adj meg érvényes, pozitív mennyiséget.',
  WebImportIssueCode.unknownUnit => 'A mértékegységet nem sikerült felismerni.',
  WebImportIssueCode.unsupportedUnit =>
    'Ez a mértékegység vagy kifejezés nem támogatott. Ellenőrizd az értelmezést.',
  WebImportIssueCode.ambiguousIngredient =>
    'A hozzávalósor értelmezése nem egyértelmű.',
  WebImportIssueCode.silentDbFallbackRisk =>
    'A felismert „db” egység félrevezető lehet. Ellenőrizd a mennyiséget és az egységet.',
  WebImportIssueCode.unresolvedQuantityExpression =>
    'A mennyiségi kifejezés ellenőrzést igényel.',
  WebImportIssueCode.missingQuantity =>
    'Hiányzó mennyiség helyett alapérték került be. Ellenőrizd.',
  WebImportIssueCode.sourceStructureWarning =>
    'A forrás szerkezete miatt ellenőrzés javasolt.',
  WebImportIssueCode.knownSourceRisk =>
    'Az automatikus import eredménye eltérhet az oldalon látható recepttől. Mentés előtt ellenőrizd a mennyiségeket.',
  WebImportIssueCode.unverifiedSource || WebImportIssueCode.unknownDomain =>
    'Ez a recept nem ellenőrzött forrásból lett automatikusan importálva. Mentés előtt ellenőrizd az adatokat.',
  _ => 'Az importált adat javítást vagy ellenőrzést igényel.',
};

class WebReviewIssueTile extends StatelessWidget {
  const WebReviewIssueTile({
    super.key,
    required this.issue,
    required this.accepted,
    required this.onAccept,
  });
  final WebImportIssue issue;
  final bool accepted;
  final VoidCallback onAccept;
  @override
  Widget build(BuildContext context) {
    final label = switch (issue.severity) {
      WebImportSeverity.info => 'Tájékoztató',
      WebImportSeverity.review => accepted ? 'Ellenőrizve' : 'Ellenőrzendő',
      WebImportSeverity.blocking => 'Javítandó',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                issue.severity == WebImportSeverity.info
                    ? Icons.info_outline
                    : accepted
                    ? Icons.check_circle_outline
                    : Icons.warning_amber_rounded,
                size: 18,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '$label: ${webReviewMessage(issue.code)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          if (issue.severity == WebImportSeverity.review && !accepted)
            TextButton(
              onPressed: onAccept,
              child: Text(switch (issue.code) {
                WebImportIssueCode.knownSourceRisk =>
                  'A mennyiségeket ellenőriztem.',
                WebImportIssueCode.unverifiedSource ||
                WebImportIssueCode.unknownDomain =>
                  'Ellenőriztem az importált receptet.',
                _ => 'Ellenőriztem',
              }),
            ),
        ],
      ),
    );
  }
}

class IngredientImportWarning extends StatelessWidget {
  const IngredientImportWarning({
    super.key,
    required this.review,
    required this.onAccept,
  });
  final WebIngredientReview review;
  final ValueChanged<WebImportIssue> onAccept;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final issue in review.issues)
        WebReviewIssueTile(
          key: ValueKey('${review.id}:${issue.identity}'),
          issue: issue,
          accepted: review.isAccepted(issue),
          onAccept: () => onAccept(issue),
        ),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text('Eredeti sor'),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(review.original.rawText),
          ),
        ],
      ),
    ],
  );
}

class WebImportReviewBanner extends StatelessWidget {
  const WebImportReviewBanner({
    super.key,
    required this.review,
    required this.onAccept,
  });
  final RecipeImportReviewMetadata review;
  final ValueChanged<WebImportIssue> onAccept;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final issue in review.issues)
        WebReviewIssueTile(
          issue: issue,
          accepted: review.isRecipeIssueAccepted(issue),
          onAccept: () => onAccept(issue),
        ),
    ],
  );
}
