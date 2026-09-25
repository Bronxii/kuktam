enum WebImportSource { mindmegette, nosalty, generic }

class WebImportSourceMetadata {
  const WebImportSourceMetadata(this.source);
  final WebImportSource source;
  bool get requiresQuantityReview => source == WebImportSource.nosalty;
  bool get unknownDomain => source == WebImportSource.generic;
  String? get titleSuffix =>
      source == WebImportSource.mindmegette ? ' | Mindmegette.hu' : null;
  String? get quantityReviewNotice => requiresQuantityReview
      ? 'Az automatikus import nem minden esetben egyezik pontosan az oldalon látható recepttel. Mentés előtt ellenőrizd a mennyiségeket.'
      : null;
}

/// Metadata, NOT an access allowlist. Text/web import and cloud sync are FREE.
class WebImportDomainPolicy {
  const WebImportDomainPolicy();
  WebImportSourceMetadata identify(Uri uri) {
    final host = uri.host.toLowerCase();
    if (const ['mindmegette.hu', 'www.mindmegette.hu'].contains(host)) {
      return const WebImportSourceMetadata(WebImportSource.mindmegette);
    }
    if (const ['nosalty.hu', 'www.nosalty.hu'].contains(host)) {
      return const WebImportSourceMetadata(WebImportSource.nosalty);
    }
    return const WebImportSourceMetadata(WebImportSource.generic);
  }
}
