import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'extractor.dart';

class FetchResponse {
  FetchResponse(this.status, this.body, this.byteCount, {this.finalUrl});
  final int status;
  final String body;
  final int byteCount;
  final String? finalUrl;
}

typedef Fetcher = Future<FetchResponse> Function(Uri url);

Future<FetchResponse> fetchHtml(Uri url) async {
  if (!['http', 'https'].contains(url.scheme) ||
      url.host.isEmpty ||
      url.userInfo.isNotEmpty) {
    throw const FormatException(
      'Only HTTP(S) URLs without credentials are supported',
    );
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    return await (() async {
      final request = await client.getUrl(url);
      request.maxRedirects = 5;
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Kuktam-Web-Import-POC/0.1',
      );
      final response = await request.close();
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
        if (bytes.length > 5 * 1024 * 1024)
          throw const FormatException('HTML exceeds 5 MiB');
      }
      var finalUrl = url;
      for (final redirect in response.redirects) {
        finalUrl = finalUrl.resolveUri(redirect.location);
      }
      String body = '';
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final encoding = response.headers.contentType?.charset ?? 'utf-8';
        final codec = Encoding.getByName(encoding);
        if (codec == null) {
          throw FormatException('Unsupported charset: $encoding');
        }
        body = codec.decode(bytes);
      }
      return FetchResponse(
        response.statusCode,
        body,
        bytes.length,
        finalUrl: finalUrl.toString(),
      );
    })().timeout(const Duration(seconds: 30));
  } finally {
    client.close(force: true);
  }
}

/// One explicit URL only. No corpus discovery or batch execution in P0.
Future<Map<String, Object?>> runUrl(String input, {Fetcher? fetcher}) async {
  final total = Stopwatch()..start();
  final fetch = Stopwatch()..start();
  final extract = Stopwatch();
  FetchResponse? response;
  Extraction? result;
  Status? failure;
  String? error;
  try {
    response = await (fetcher ?? fetchHtml)(Uri.parse(input));
    fetch.stop();
    if (response.status < 200 || response.status >= 300) {
      failure = Status.httpError;
    } else {
      extract.start();
      result = extractRecipes(response.body);
    }
  } catch (e) {
    failure = response == null ? Status.fetchError : Status.invalidJsonLd;
    error = e.toString();
  } finally {
    fetch.stop();
    extract.stop();
    total.stop();
  }
  return {
    'url': input,
    'http_status': response?.status,
    'html_bytes': response?.byteCount,
    'final_url': response?.finalUrl,
    'fetch_ms': fetch.elapsedMicroseconds / 1000,
    'extract_ms': extract.elapsedMicroseconds / 1000,
    'total_ms': total.elapsedMicroseconds / 1000,
    if (result != null)
      ...result.toJson()
    else ...{
      'status': failure!.code,
      'json_ld_blocks': 0,
      'recipe_candidates': 0,
      'candidates': <Object>[],
      'warnings': [if (error != null) error],
    },
  };
}
