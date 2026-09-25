import '../../domain/models/web_import_issue.dart';

String webImportErrorMessage(Object error) {
  final code = error is WebImportFailure
      ? error.code
      : WebImportIssueCode.fetchError;
  return switch (code) {
    WebImportIssueCode.accessBlocked =>
      'Erről az oldalról jelenleg nem tudjuk automatikusan beolvasni a receptet. Másold be a recept szövegét.',
    WebImportIssueCode.rateLimited =>
      'Az oldal most túl sok kérést kap. Próbáld újra később, vagy másold be a recept szövegét.',
    WebImportIssueCode.timeout =>
      'Az oldal túl lassan válaszolt. Próbáld újra, vagy másold be a recept szövegét.',
    WebImportIssueCode.multipleRecipes =>
      'Az oldalon több receptet találtunk. Másold be a kívánt recept szövegét.',
    WebImportIssueCode.noRecipe ||
    WebImportIssueCode.invalidRecipe ||
    WebImportIssueCode.missingTitle ||
    WebImportIssueCode.missingIngredients ||
    WebImportIssueCode.missingPreparation =>
      'Az oldal szerkezete alapján nem sikerült receptet felismerni. Másold be a recept szövegét.',
    WebImportIssueCode.tooLarge =>
      'Az oldal túl nagy az automatikus importhoz. Másold be a recept szövegét.',
    WebImportIssueCode.invalidEncoding =>
      'Az oldal szövegét nem sikerült beolvasni. Másold be a recept szövegét.',
    WebImportIssueCode.invalidUrl || WebImportIssueCode.unsafeTarget =>
      'Ez a link nem használható biztonságos webimporthoz. Ellenőrizd, vagy másold be a recept szövegét.',
    WebImportIssueCode.invalidContentType =>
      'A link nem feldolgozható receptoldalra mutat. Másold be a recept szövegét.',
    _ =>
      'Nem sikerült elérni vagy feldolgozni az oldalt. Próbáld újra, vagy másold be a recept szövegét.',
  };
}
