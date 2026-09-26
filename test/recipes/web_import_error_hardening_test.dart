import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/recipes/data/services/web_recipe_fetcher.dart';
import 'package:kuktam/recipes/data/services/web_recipe_import_loader.dart';
import 'package:kuktam/recipes/domain/models/web_import_issue.dart';
import 'package:kuktam/recipes/presentation/widgets/web_import_error_message.dart';
import 'web_recipe_fetcher_test.dart' as fixtures;
import 'recipe_web_import_dialog_test.dart' as dialog;

WebRecipeFetcher fetcher(
  fixtures.FakeTransport t, {
  WebDnsResolver? dns,
  int max = 10,
}) => WebRecipeFetcher(
  transport: () => t,
  resolve: dns ?? (_) async => [InternetAddress('8.8.8.8')],
  maxBytes: max,
);

void main() {
  test(
    'DNS exception/empty result is distinct from connect/reset; no retry',
    () async {
      for (final empty in [false, true]) {
        final t = fixtures.FakeTransport((_) async => fixtures.html());
        await expectLater(
          fetcher(
            t,
            dns: (_) async {
              if (empty) return [];
              throw const SocketException('secret DNS');
            },
          ).fetch('https://a.example'),
          fixtures.failure(WebImportIssueCode.dnsFailure),
        );
        expect(t.calls, isEmpty);
        expect(t.closed, true);
      }
      for (final code in [61, 104]) {
        final t = fixtures.FakeTransport(
          (_) async => throw SocketException(
            'secret socket',
            osError: OSError('private', code),
          ),
        );
        await expectLater(
          fetcher(t).fetch('https://a.example'),
          fixtures.failure(WebImportIssueCode.connectionFailure),
        );
        expect(t.calls.length, 1);
      }
    },
  );

  for (final status in [403, 404, 429, 400, 500, 503]) {
    test('HTTP $status status preserved without retry or raw text', () async {
      final t = fixtures.FakeTransport(
        (_) async => fixtures.html(status: status),
      );
      try {
        await fetcher(t).fetch('https://a.example');
        fail('must fail');
      } on WebImportFailure catch (e) {
        expect(e.httpStatus, status);
        expect(webImportErrorMessage(e), isNot(contains('Exception')));
        if (status == 404) {
          expect(webImportErrorMessage(e), contains('nem található'));
        }
      }
      expect(t.calls.length, 1);
    });
  }

  test('redirect loop rejected before repeating request', () async {
    final t = fixtures.FakeTransport(
      (u) async => fixtures.html(
        status: 302,
        headers: {'location': u.path == '/a' ? '/b' : '/a'},
      ),
    );
    await expectLater(
      fetcher(t).fetch('https://a.example/a'),
      fixtures.failure(WebImportIssueCode.redirectLoop),
    );
    expect(t.calls.length, 2);
  });

  test(
    'oversized Content-Length rejected before subscribing to body',
    () async {
      var listened = false;
      final body = StreamController<List<int>>(onListen: () => listened = true);
      final t = fixtures.FakeTransport(
        (_) async => WebFetchResponse(200, {
          'content-type': 'text/html',
          'content-length': '11',
        }, body.stream),
      );
      await expectLater(
        fetcher(t).fetch('https://a.example'),
        fixtures.failure(WebImportIssueCode.tooLarge),
      );
      expect(listened, false);
      unawaited(body.close());
    },
  );

  test('stream over limit and cancellation cancel body subscription', () async {
    for (final cancel in [false, true]) {
      var detached = false;
      final body = StreamController<List<int>>(onCancel: () => detached = true);
      final t = fixtures.FakeTransport(
        (_) async =>
            WebFetchResponse(200, {'content-type': 'text/html'}, body.stream),
      );
      final token = WebImportCancellation();
      final future = fetcher(t).fetch('https://a.example', cancellation: token);
      final assertion = expectLater(
        future,
        fixtures.failure(
          cancel ? WebImportIssueCode.cancelled : WebImportIssueCode.tooLarge,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      if (cancel) {
        token.cancel();
      } else {
        body.add(List.filled(11, 65));
      }
      await assertion;
      await Future<void>.delayed(Duration.zero);
      expect(detached, true);
      expect(t.closed, true);
      await body.close();
    }
  });

  test(
    'gzip decompressed body exceeds limit despite small compressed length',
    () async {
      final compressed = gzip.encode(List.filled(1000, 65));
      final t = fixtures.FakeTransport(
        (_) async => WebFetchResponse(200, {
          'content-type': 'text/html',
          'content-encoding': 'gzip',
          'content-length': '${compressed.length}',
        }, Stream.value(gzip.decode(compressed))),
      );
      await expectLater(
        fetcher(t, max: 100).fetch('https://a.example'),
        fixtures.failure(WebImportIssueCode.tooLarge),
      );
    },
  );

  test(
    'missing/unsupported content type and invalid charset fail without partial result',
    () async {
      for (final headers in [
        <String, String>{},
        {'content-type': 'image/png'},
      ]) {
        final t = fixtures.FakeTransport(
          (_) async => fixtures.html(headers: headers),
        );
        await expectLater(
          fetcher(t).fetch('https://a.example'),
          fixtures.failure(WebImportIssueCode.invalidContentType),
        );
      }
      for (final charset in ['made-up', 'utf-8']) {
        final t = fixtures.FakeTransport(
          (_) async => WebFetchResponse(200, {
            'content-type': 'text/html; charset=$charset',
          }, Stream.value([255])),
        );
        await expectLater(
          fetcher(t).fetch('https://a.example'),
          fixtures.failure(WebImportIssueCode.invalidEncoding),
        );
      }
    },
  );

  test(
    'loader retains distinct source failures and rejects empty/invalid drafts',
    () async {
      final fetch = dialog.Fetch();
      final loader = WebRecipeImportLoader(fetcher: fetch);
      for (final entry in <(String, WebImportIssueCode)>[
        ('<html>none', WebImportIssueCode.noJsonLd),
        (
          '<script type="application/ld+json">{broken</script>',
          WebImportIssueCode.invalidJsonLd,
        ),
        (
          '<script type="application/ld+json">{"@type":"Person"}</script>',
          WebImportIssueCode.noRecipe,
        ),
        (
          '<script type="application/ld+json">{"@type":"Recipe"}</script>',
          WebImportIssueCode.invalidRecipe,
        ),
        (
          dialog.htmlRecipe() + dialog.htmlRecipe(),
          WebImportIssueCode.multipleRecipes,
        ),
        (
          dialog.htmlRecipe(rows: ['0 g liszt']),
          WebImportIssueCode.invalidRecipe,
        ),
      ]) {
        fetch.body = entry.$1;
        await expectLater(
          loader.load(
            'https://a.example',
            cancellation: WebImportCancellation(),
            importId: 'test',
          ),
          fixtures.failure(entry.$2),
        );
      }
    },
  );

  test(
    'unexpected loader failure becomes controlled internal failure',
    () async {
      await expectLater(
        WebRecipeImportLoader(fetcher: _Broken()).load(
          'https://a.example',
          cancellation: WebImportCancellation(),
          importId: 'test',
        ),
        fixtures.failure(WebImportIssueCode.internalFailure),
      );
    },
  );
}

class _Broken extends WebRecipeFetcher {
  @override
  Future<WebFetchedHtml> fetch(
    String input, {
    WebImportCancellation? cancellation,
  }) async => throw StateError('SECRET');
}
