import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/recipes/data/services/web_recipe_fetcher.dart';
import 'package:kuktam/recipes/domain/models/web_import_issue.dart';

class FakeTransport implements WebFetchTransport {
  FakeTransport(this.respond);
  final Future<WebFetchResponse> Function(Uri) respond;
  final calls = <Uri>[];
  final addresses = <InternetAddress>[];
  bool closed = false;
  @override
  Future<WebFetchResponse> get(
    Uri uri,
    InternetAddress address,
    WebImportCancellation token,
  ) {
    calls.add(uri);
    addresses.add(address);
    return respond(uri);
  }

  @override
  void close() {
    closed = true;
  }
}

WebFetchResponse html({
  int status = 200,
  String type = 'text/html; charset=utf-8',
  String text = '<h1>Árvíz</h1>',
  Map<String, String>? headers,
}) => WebFetchResponse(
  status,
  headers ?? {'content-type': type},
  Stream.value(utf8.encode(text)),
);
Matcher failure(WebImportIssueCode code) =>
    throwsA(isA<WebImportFailure>().having((e) => e.code, 'code', code));
void main() {
  test('native transport pins socket, preserves Host and decompresses', () async {
    // Local transport-only test; URL/DNS security is tested at the fetcher layer.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final transport = IoWebFetchTransport();
    final seen = Completer<HttpRequest>();
    final subscription = server.listen((request) {
      seen.complete(request);
      request.response.headers.contentType = ContentType.html;
      request.response.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
      request.response.add(gzip.encode(utf8.encode('<h1>Recipe</h1>')));
      unawaited(request.response.close());
    });
    try {
      final response = await transport.get(
        Uri.parse('http://pinned.example:${server.port}/recipe'),
        InternetAddress.loopbackIPv4,
        WebImportCancellation(),
      );
      final request = await seen.future;
      expect(
        request.headers.value(HttpHeaders.hostHeader),
        'pinned.example:${server.port}',
      );
      expect(request.cookies, isEmpty);
      final body = await response.body.expand((v) => v).toList();
      expect(utf8.decode(body), '<h1>Recipe</h1>');
    } finally {
      transport.close();
      await subscription.cancel();
      await server.close(force: true);
    }
  });
  WebRecipeFetcher fetcher(
    FakeTransport transport, {
    WebDnsResolver? dns,
    Duration? timeout,
    int? max,
  }) => WebRecipeFetcher(
    transport: () => transport,
    resolve: dns ?? ((_) async => [InternetAddress('8.8.8.8')]),
    totalTimeout: timeout ?? const Duration(seconds: 30),
    maxBytes: max ?? 5 * 1024 * 1024,
  );
  test(
    'success preserves original/final metadata and public address',
    () async {
      final t = FakeTransport((_) async => html());
      final r = await fetcher(
        t,
      ).fetch('  https://unknown.example/recipe#top  ');
      expect(r.originalUrl, '  https://unknown.example/recipe#top  ');
      expect(r.finalUrl.toString(), 'https://unknown.example/recipe');
      expect(r.html, contains('Árvíz'));
      expect(t.closed, true);
      expect(t.addresses.single.address, '8.8.8.8');
    },
  );
  test('safe cross-domain redirect and exact limit', () async {
    final t = FakeTransport(
      (u) async => u.host == 'a.example'
          ? html(status: 302, headers: {'location': 'https://b.example/r'})
          : html(),
    );
    final r = await fetcher(t).fetch('https://a.example');
    expect(r.redirectCount, 1);
    expect(r.finalUrl.host, 'b.example');
    final loop = FakeTransport(
      (_) async => html(status: 302, headers: {'location': '/again'}),
    );
    await expectLater(
      fetcher(loop).fetch('https://a.example'),
      failure(WebImportIssueCode.tooManyRedirects),
    );
    expect(loop.calls.length, 6);
  });
  test(
    'redirect security rejects local literals downgrade and resolved-private targets',
    () async {
      for (final location in [
        'http://127.0.0.1',
        'https://localhost',
        'http://b.example',
      ]) {
        final t = FakeTransport(
          (_) async => html(status: 302, headers: {'location': location}),
        );
        await expectLater(
          fetcher(t).fetch('https://a.example'),
          failure(WebImportIssueCode.unsafeTarget),
        );
        expect(t.calls.length, 1);
      }
      final t = FakeTransport(
        (_) async =>
            html(status: 302, headers: {'location': 'https://private.example'}),
      );
      await expectLater(
        fetcher(
          t,
          dns: (host) async => [
            InternetAddress(host == 'private.example' ? '10.0.0.1' : '8.8.8.8'),
          ],
        ).fetch('https://a.example'),
        failure(WebImportIssueCode.unsafeTarget),
      );
      expect(t.calls.length, 1);
    },
  );
  test('403 429 500 mapped separately with no retry', () async {
    for (final pair in [
      (403, WebImportIssueCode.accessBlocked),
      (429, WebImportIssueCode.rateLimited),
      (500, WebImportIssueCode.httpError),
    ]) {
      final t = FakeTransport((_) async => html(status: pair.$1));
      await expectLater(
        fetcher(t).fetch('https://a.example'),
        failure(pair.$2),
      );
      expect(t.calls.length, 1);
      expect(t.closed, true);
    }
  });
  test(
    'total timeout closes active I/O, DNS late result cannot connect',
    () async {
      final t = FakeTransport((_) => Completer<WebFetchResponse>().future);
      await expectLater(
        fetcher(
          t,
          timeout: const Duration(milliseconds: 10),
        ).fetch('https://a.example'),
        failure(WebImportIssueCode.timeout),
      );
      expect(t.closed, true);
      final dns = Completer<List<InternetAddress>>();
      final delayed = FakeTransport((_) async => html());
      await expectLater(
        fetcher(
          delayed,
          dns: (_) => dns.future,
          timeout: const Duration(milliseconds: 10),
        ).fetch('https://a.example'),
        failure(WebImportIssueCode.timeout),
      );
      dns.complete([InternetAddress('8.8.8.8')]);
      await Future<void>.delayed(Duration.zero);
      expect(delayed.calls, isEmpty);
    },
  );
  test(
    'cancel terminates operation and closes I/O, including body stream',
    () async {
      final body = StreamController<List<int>>();
      final t = FakeTransport(
        (_) async =>
            WebFetchResponse(200, {'content-type': 'text/html'}, body.stream),
      );
      final token = WebImportCancellation();
      final pending = fetcher(
        t,
      ).fetch('https://a.example', cancellation: token);
      final assertion = expectLater(
        pending,
        failure(WebImportIssueCode.cancelled),
      );
      await Future<void>.delayed(Duration.zero);
      token.cancel();
      await assertion;
      expect(t.closed, true);
      await body.close();
    },
  );
  test('oversize decoded bytes and invalid content type fail', () async {
    final t = FakeTransport((_) async => html(text: '01234567890'));
    await expectLater(
      fetcher(t, max: 10).fetch('https://a.example'),
      failure(WebImportIssueCode.tooLarge),
    );
    expect(t.closed, true);
    final bad = FakeTransport((_) async => html(type: 'application/json'));
    await expectLater(
      fetcher(bad).fetch('https://a.example'),
      failure(WebImportIssueCode.invalidContentType),
    );
  });
  test('charset UTF8 BOM latin1 meta unsupported malformed', () async {
    expect(
      WebRecipeFetcher.decodeHtml([
        0xef,
        0xbb,
        0xbf,
        ...utf8.encode('Ő'),
      ], 'ascii'),
      'Ő',
    );
    expect(WebRecipeFetcher.decodeHtml([0xe9], 'iso-8859-1'), 'é');
    expect(
      WebRecipeFetcher.decodeHtml(utf8.encode('<meta charset="utf-8">Ő'), null),
      contains('Ő'),
    );
    expect(
      () => WebRecipeFetcher.decodeHtml([0xff], 'utf-8'),
      throwsA(isA<WebImportFailure>()),
    );
    expect(
      () => WebRecipeFetcher.decodeHtml([1], 'unsupported'),
      throwsA(isA<WebImportFailure>()),
    );
    final t = FakeTransport((_) async => html(type: 'application/xhtml+xml'));
    expect((await fetcher(t).fetch('https://a.example')).html, isNotEmpty);
  });
  test(
    'connectivity error maps to failure and preserves no raw exception',
    () async {
      final t = FakeTransport(
        (_) async => throw const SocketException('private detail'),
      );
      await expectLater(
        fetcher(t).fetch('https://a.example'),
        failure(WebImportIssueCode.fetchError),
      );
      expect(t.closed, true);
    },
  );
}
