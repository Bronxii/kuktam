import 'dart:io';
import '../models/web_import_issue.dart';
import 'recipe_import_input_classifier.dart';

class WebImportUrlValidator {
  const WebImportUrlValidator();
  Uri validate(String input, {Uri? previous}) {
    validateReference(input);
    final uri = const RecipeImportInputClassifier().url(input);
    if (uri == null) {
      throw const WebImportFailure(WebImportIssueCode.invalidUrl);
    }
    final host = uri.host.toLowerCase();
    if (uri.authority.contains('@') ||
        uri.hasPort && uri.port != (uri.scheme == 'https' ? 443 : 80) ||
        previous?.scheme == 'https' && uri.scheme != 'https' ||
        host.endsWith('.') ||
        !host.contains('.') ||
        host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local') ||
        InternetAddress.tryParse(host) != null ||
        !RegExp(
          r'^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z][a-z0-9-]{0,62}$',
        ).hasMatch(host)) {
      throw const WebImportFailure(WebImportIssueCode.unsafeTarget);
    }
    return uri.removeFragment();
  }

  // Uri canonicalization removes empty userinfo; inspect the raw authority first.
  void validateReference(String input) {
    if (RegExp(
      r'^(?:https?:)?//[^/?#]*@',
      caseSensitive: false,
    ).hasMatch(input.trim())) {
      throw const WebImportFailure(WebImportIssueCode.unsafeTarget);
    }
  }

  /// Conservative public-unicast policy; reject mixed public/private DNS answers.
  bool isPublic(InternetAddress address) {
    final b = address.rawAddress;
    if (b.length == 4) {
      if (b[0] == 0 ||
          b[0] == 10 ||
          b[0] == 127 ||
          b[0] >= 224 ||
          b[0] == 100 && b[1] >= 64 && b[1] <= 127 ||
          b[0] == 169 && b[1] == 254 ||
          b[0] == 172 && b[1] >= 16 && b[1] <= 31 ||
          b[0] == 192 && b[1] == 168 ||
          b[0] == 192 && b[1] == 0 ||
          b[0] == 192 && b[1] == 88 && b[2] == 99 ||
          b[0] == 198 &&
              (b[1] == 18 || b[1] == 19 || b[1] == 51 && b[2] == 100) ||
          b[0] == 203 && b[1] == 0 && b[2] == 113) {
        return false;
      }
      return true;
    }
    // Global unicast only; reject mapped IPv4, NAT64, ULA, link-local,
    // multicast, documentation, 6to4 and special 2001::/23 allocations.
    return b.length == 16 &&
        b[0] & 0xe0 == 0x20 &&
        !(b[0] == 0x20 && b[1] == 0x01 && b[2] < 2) &&
        !(b[0] == 0x20 && b[1] == 0x01 && b[2] == 0x0d && b[3] == 0xb8) &&
        !(b[0] == 0x20 && b[1] == 0x02) &&
        !(b[0] == 0x3f && b[1] == 0xff && b[2] < 0x10);
  }

  void validateAddresses(List<InternetAddress> addresses) {
    if (addresses.isEmpty || addresses.any((a) => !isPublic(a))) {
      throw const WebImportFailure(WebImportIssueCode.unsafeTarget);
    }
  }
}
