import 'web_import_issue.dart';

enum WebImportQuality { pass, review, fail }

class WebImportQualityResult {
  WebImportQualityResult(this.quality, Iterable<WebImportIssue> issues)
    : issues = List.unmodifiable(issues);
  final WebImportQuality quality;
  final List<WebImportIssue> issues;

  /// P6.1 checks structure only. Parser diagnostics are supplied by P6.2.
  bool get allowsHandoff => quality != WebImportQuality.fail;
}
