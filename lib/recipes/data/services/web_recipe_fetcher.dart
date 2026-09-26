import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../domain/models/web_import_issue.dart';
import '../../domain/services/web_import_url_validator.dart';

class WebImportCancellation {
  final _listeners = <void Function()>[];
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void check() {
    if (_cancelled) throw const WebImportFailure(WebImportIssueCode.cancelled);
  }

  void Function() listen(void Function() callback) {
    if (_cancelled) {
      callback();
      return () {};
    }
    _listeners.add(callback);
    return () => _listeners.remove(callback);
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final callback in List.of(_listeners)) {
      callback();
    }
    _listeners.clear();
  }
}

class WebFetchResponse {
  WebFetchResponse(this.status, this.headers, this.body);
  final int status;
  final Map<String, String> headers;

  /// Transport supplies decompressed bytes. Never an unbounded collected body.
  final Stream<List<int>> body;
}

abstract interface class WebFetchTransport {
  Future<WebFetchResponse> get(
    Uri uri,
    InternetAddress address,
    WebImportCancellation cancellation,
  );
  void close();
}

class IoWebFetchTransport implements WebFetchTransport {
  IoWebFetchTransport() : _client = HttpClient() {
    _client.connectionTimeout = const Duration(seconds: 20);
    _client.autoUncompress = true;
    _client.findProxy = (_) => 'DIRECT';
  }
  final HttpClient _client;
  @override
  Future<WebFetchResponse> get(
    Uri uri,
    InternetAddress address,
    WebImportCancellation cancellation,
  ) async {
    cancellation.check();
    _client.connectionFactory = (target, proxyHost, proxyPort) async {
      cancellation.check();
      // The HTTP/TLS target remains the original hostname; only the socket
      // address is pinned. HttpClient performs normal TLS certificate checking.
      final task = await Socket.startConnect(address, target.port);
      if (cancellation.isCancelled) {
        task.cancel();
        cancellation.check();
      }
      final remove = cancellation.listen(task.cancel);
      unawaited(
        task.socket.then<void>(
          (_) {
            remove();
          },
          onError: (Object e, StackTrace s) {
            remove();
          },
        ),
      );
      return task;
    };
    final request = await _client.getUrl(uri);
    cancellation.check();
    request.followRedirects = false;
    request.persistentConnection = false;
    request.headers.set(HttpHeaders.userAgentHeader, 'Kuktam-Web-Import/1.0');
    request.headers.set(
      HttpHeaders.acceptHeader,
      'text/html, application/xhtml+xml',
    );
    request.cookies.clear();
    final response = await request.close();
    cancellation.check();
    return WebFetchResponse(response.statusCode, {
      for (final name in [
        HttpHeaders.locationHeader,
        HttpHeaders.contentTypeHeader,
        HttpHeaders.contentLengthHeader,
        HttpHeaders.contentEncodingHeader,
      ])
        if (response.headers.value(name) != null)
          name: response.headers.value(name)!,
    }, response);
  }

  @override
  void close() => _client.close(force: true);
}

class WebFetchedHtml {
  const WebFetchedHtml({
    required this.originalUrl,
    required this.finalUrl,
    required this.html,
    required this.byteCount,
    required this.redirectCount,
  });
  final String originalUrl;
  final Uri finalUrl;
  final String html;
  final int byteCount;
  final int redirectCount;
}

typedef WebDnsResolver = Future<List<InternetAddress>> Function(String host);

class WebRecipeFetcher {
  WebRecipeFetcher({
    WebDnsResolver? resolve,
    WebFetchTransport Function()? transport,
    this.totalTimeout = const Duration(seconds: 30),
    this.maxBytes = 5 * 1024 * 1024,
  }) : _resolve = resolve ?? InternetAddress.lookup,
       _transport = transport ?? IoWebFetchTransport.new;
  final WebDnsResolver _resolve;
  final WebFetchTransport Function() _transport;
  final Duration totalTimeout;
  final int maxBytes;
  static const _validator = WebImportUrlValidator();
  Future<WebFetchedHtml> fetch(
    String input, {
    WebImportCancellation? cancellation,
  }) async {
    final initial = _validator.validate(input);
    cancellation?.check();
    final io = _transport();
    final internal = WebImportCancellation();
    final aborted = Completer<WebFetchedHtml>();
    void abort(WebImportIssueCode reason) {
      if (aborted.isCompleted) return;
      internal.cancel();
      io.close();
      aborted.completeError(WebImportFailure(reason));
    }

    final timer = Timer(totalTimeout, () => abort(WebImportIssueCode.timeout));
    final remove = cancellation?.listen(
      () => abort(WebImportIssueCode.cancelled),
    );
    try {
      return await Future.any([
        _fetch(input, initial, io, internal),
        aborted.future,
      ]);
    } on WebImportFailure {
      rethrow;
    } on TimeoutException {
      throw const WebImportFailure(WebImportIssueCode.timeout);
    } on SocketException {
      throw const WebImportFailure(WebImportIssueCode.connectionFailure);
    } on HandshakeException {
      throw const WebImportFailure(WebImportIssueCode.connectionFailure);
    } on FormatException {
      throw const WebImportFailure(WebImportIssueCode.invalidContentType);
    } catch (_) {
      throw const WebImportFailure(WebImportIssueCode.fetchError);
    } finally {
      timer.cancel();
      remove?.call();
      internal.cancel();
      io.close();
    }
  }

  Future<WebFetchedHtml> _fetch(
    String original,
    Uri uri,
    WebFetchTransport io,
    WebImportCancellation token,
  ) async {
    var redirects = 0;
    final visited = <Uri>{};
    while (true) {
      token.check();
      if (!visited.add(uri)) {
        throw const WebImportFailure(WebImportIssueCode.redirectLoop);
      }
      List<InternetAddress> addresses;
      try {
        addresses = await _resolve(uri.host);
      } on TimeoutException {
        rethrow;
      } on SocketException {
        throw const WebImportFailure(WebImportIssueCode.dnsFailure);
      }
      if (addresses.isEmpty) {
        throw const WebImportFailure(WebImportIssueCode.dnsFailure);
      }
      token.check();
      _validator.validateAddresses(addresses);
      final response = await io.get(uri, addresses.first, token);
      token.check();
      if (const [301, 302, 303, 307, 308].contains(response.status)) {
        // Cancel body consumption rather than buffering redirect/error pages.
        await response.body.listen((_) {}).cancel();
        if (redirects >= 5) {
          throw const WebImportFailure(WebImportIssueCode.tooManyRedirects);
        }
        final location = response.headers[HttpHeaders.locationHeader];
        if (location == null) {
          throw const WebImportFailure(WebImportIssueCode.invalidUrl);
        }
        _validator.validateReference(location);
        uri = _validator.validate(
          uri.resolve(location).toString(),
          previous: uri,
        );
        redirects++;
        continue;
      }
      if (response.status < 200 || response.status >= 300) {
        await response.body.listen((_) {}).cancel();
        throw WebImportFailure(
          response.status == 403
              ? WebImportIssueCode.accessBlocked
              : response.status == 429
              ? WebImportIssueCode.rateLimited
              : WebImportIssueCode.httpError,
          httpStatus: response.status,
        );
      }
      final header = response.headers[HttpHeaders.contentTypeHeader];
      final type = header == null ? null : ContentType.parse(header);
      if (type == null ||
          ![
            'text/html',
            'application/xhtml+xml',
          ].contains(type.mimeType.toLowerCase())) {
        throw const WebImportFailure(WebImportIssueCode.invalidContentType);
      }
      final length = int.tryParse(
        response.headers[HttpHeaders.contentLengthHeader] ?? '',
      );
      final encoding = response.headers[HttpHeaders.contentEncodingHeader];
      // Compressed Content-Length is not the decompressed body size.
      if ((encoding == null || encoding.toLowerCase() == 'identity') &&
          length != null &&
          length > maxBytes) {
        throw const WebImportFailure(WebImportIssueCode.tooLarge);
      }
      final bytes = <int>[];
      final chunks = StreamIterator<List<int>>(response.body);
      final removeBodyCancellation = token.listen(() {
        unawaited(chunks.cancel());
      });
      try {
        while (await chunks.moveNext()) {
          token.check();
          final chunk = chunks.current;
          if (bytes.length + chunk.length > maxBytes) {
            throw const WebImportFailure(WebImportIssueCode.tooLarge);
          }
          bytes.addAll(chunk);
        }
      } finally {
        removeBodyCancellation();
        await chunks.cancel();
      }
      token.check();
      final html = decodeHtml(bytes, type.charset);
      return WebFetchedHtml(
        originalUrl: original,
        finalUrl: uri,
        html: html,
        byteCount: bytes.length,
        redirectCount: redirects,
      );
    }
  }

  /// UTF-8 BOM > HTTP charset > HTML charset > strict UTF-8 default.
  /// Unsupported charsets fail explicitly; no silent replacement characters.
  static String decodeHtml(List<int> bytes, String? charset) {
    try {
      if (bytes.length >= 3 &&
          bytes[0] == 0xef &&
          bytes[1] == 0xbb &&
          bytes[2] == 0xbf) {
        return utf8.decode(bytes.sublist(3));
      }
      final prefix = latin1.decode(bytes.take(2048).toList());
      final meta = RegExp(
        r'charset\s*=\s*["\x27]?([a-zA-Z0-9_-]+)',
        caseSensitive: false,
      ).firstMatch(prefix);
      final name = (charset ?? meta?.group(1) ?? 'utf-8').toLowerCase();
      final codec = Encoding.getByName(name);
      if (codec == null) {
        throw const WebImportFailure(WebImportIssueCode.invalidEncoding);
      }
      return codec.decode(bytes);
    } on WebImportFailure {
      rethrow;
    } catch (_) {
      throw const WebImportFailure(WebImportIssueCode.invalidEncoding);
    }
  }
}
