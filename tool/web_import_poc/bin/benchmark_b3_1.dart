import 'dart:convert';
import 'dart:io';
import 'package:kuktam_web_import_poc/runner.dart';

Map<String, double> stats(List<double> values) {
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  return {
    'average': sorted.reduce((a, b) => a + b) / sorted.length,
    'median': sorted.length.isEven
        ? (sorted[middle - 1] + sorted[middle]) / 2
        : sorted[middle],
    'min': sorted.first,
    'max': sorted.last,
  };
}

Future<void> main(List<String> args) async {
  if (args.length != 1 || args.single != '--run-batch-21-30') {
    stderr.writeln('Explicit approval required: --run-batch-21-30');
    exitCode = 64;
    return;
  }
  final directory = Directory('results');
  await directory.create(recursive: true);
  final output = File('results/b3_1_batch_21-30.json');
  final journal = File('results/b3_1_batch_21-30.jsonl');
  if (output.existsSync() || journal.existsSync()) {
    throw StateError(
      'Existing results: refusing accidental repeated requests.',
    );
  }
  // Validate every authorized URL before making any network request.
  final inputs = <({String id, String url})>[];
  for (var i = 21; i <= 30; i++) {
    final id = i.toString().padLeft(2, '0');
    final url = File(
      '../../test/fixtures/web_import_corpus/batch_3_21-30/website_$id.txt',
    ).readAsStringSync().trim();
    final uri = Uri.parse(url);
    if (uri.scheme != 'https' || uri.host.isEmpty || url.contains('\n')) {
      throw FormatException('Invalid website_$id.txt');
    }
    inputs.add((id: id, url: url));
  }
  final started = DateTime.now().toUtc().toIso8601String();
  final results = <Map<String, Object?>>[];
  for (final input in inputs) {
    // Record the attempt before dispatch. No automatic retry, even after a crash.
    journal.writeAsStringSync(
      '${jsonEncode({'event': 'start', 'id': input.id, 'url': input.url})}\n',
      mode: FileMode.append,
      flush: true,
    );
    FetchResponse? captured;
    final result = await runUrl(
      input.url,
      fetcher: (uri) async {
        captured = await fetchHtml(uri);
        return captured!;
      },
    );
    final candidates = (result['candidates'] as List)
        .cast<Map<String, Object?>>();
    final single = candidates.length == 1 ? candidates.single : null;
    final warnings = <Object?>[
      ...result['warnings'] as List,
      for (var i = 0; i < candidates.length; i++)
        for (final warning in candidates[i]['warnings'] as List)
          'Candidate ${i + 1}: $warning',
    ];
    final record = <String, Object?>{
      ...result,
      'id': input.id,
      'domain': Uri.parse(input.url).host,
      'attempt': 1,
      'extraction_executed':
          result['http_status'] is int &&
          (result['http_status'] as int) >= 200 &&
          (result['http_status'] as int) < 300,
      'response_body_policy':
          'Existing fetchHtml counts full response bytes but retains/decodes body only for 2xx. Error body not saved; error JSON-LD presence unexamined. Zero candidate/block count on HTTP errors means extraction skipped, not verified absence.',
      'access_limitation': result['http_status'] == 403,

      'retry': false,
      'title': single?['title'],
      'ingredient_count': single?['ingredient_count'],
      'instruction_count': single?['instruction_count'],
      'json_ld_block_count': result['json_ld_blocks'],
      'recipe_candidate_count': result['recipe_candidates'],
      'warnings': warnings,
      'error': result['status'] == 'FETCH_ERROR'
          ? warnings.join('; ')
          : result['status'] == 'HTTP_ERROR'
          ? 'HTTP ${result['http_status']}'
          : null,
      'html_snapshot': captured?.body.isNotEmpty == true
          ? 'b3_1_html/source_${input.id}.html'
          : null,
    };
    // Snapshot/report I/O is outside the measured URL pipeline.
    if (captured?.body.isNotEmpty == true) {
      Directory('results/b3_1_html').createSync(recursive: true);
      File(
        'results/b3_1_html/source_${input.id}.html',
      ).writeAsStringSync(captured!.body);
    }
    final previous = File('results/b3_0_sources/source_${input.id}.html');
    record['snapshot_comparison'] = {
      'b3_0_snapshot': 'b3_0_sources/source_${input.id}.html',
      'method':
          'Exact decoded HTML string equality, no recipe content comparison',
      'status': captured?.body.isNotEmpty != true || !previous.existsSync()
          ? 'UNAVAILABLE'
          : previous.readAsStringSync() == captured!.body
          ? 'IDENTICAL'
          : 'DIFFERENT',
      'b3_0_snapshot_bytes': previous.existsSync()
          ? previous.lengthSync()
          : null,
    };
    record['final_url_differs'] =
        result['final_url'] != null && result['final_url'] != input.url;
    results.add(record);
    journal.writeAsStringSync(
      '${jsonEncode({'event': 'result', ...record})}\n',
      mode: FileMode.append,
      flush: true,
    );
    stdout.writeln(
      '${input.id}: ${record['status']} HTTP ${record['http_status']} total=${record['total_ms']}ms',
    );
  }
  final counts = <String, int>{
    for (final s in [
      'SUCCESS',
      'MULTIPLE_RECIPES',
      'NO_RECIPE',
      'NO_JSON_LD',
      'HTTP_ERROR',
      'FETCH_ERROR',
      'INVALID_JSON_LD',
      'INVALID_RECIPE',
    ])
      s: results.where((r) => r['status'] == s).length,
  };
  final successful = results.where((r) => r['status'] == 'SUCCESS').toList();
  final errors = results.where((r) => r['status'] == 'HTTP_ERROR').toList();
  final sorted = [...successful]
    ..sort(
      (a, b) => (a['total_ms'] as double).compareTo(b['total_ms'] as double),
    );
  final summary = {
    'total_urls': 10,
    'domains': {
      for (final domain in results.map((r) => r['domain'] as String).toSet())
        domain: {
          'total': results.where((r) => r['domain'] == domain).length,
          'success_rate_percent':
              results
                  .where(
                    (r) => r['domain'] == domain && r['status'] == 'SUCCESS',
                  )
                  .length /
              results.where((r) => r['domain'] == domain).length *
              100,
          'status_counts': {
            for (final status in counts.keys)
              status: results
                  .where((r) => r['domain'] == domain && r['status'] == status)
                  .length,
          },
        },
    },
    'status_counts': counts,
    'downloaded_2xx': results
        .where(
          (r) =>
              r['http_status'] is int &&
              (r['http_status'] as int) >= 200 &&
              (r['http_status'] as int) < 300,
        )
        .length,
    'urls_with_recipe': results
        .where((r) => (r['recipe_candidate_count'] as int) > 0)
        .length,
    'success_rate_percent': counts['SUCCESS']! * 10,
    for (final key in ['fetch_ms', 'extract_ms', 'total_ms'])
      key: successful.isEmpty
          ? null
          : stats(successful.map((r) => r[key] as double).toList()),
    'http_error_timings': [
      for (final r in errors)
        {
          for (final k in [
            'id',
            'http_status',
            'fetch_ms',
            'extract_ms',
            'total_ms',
          ])
            k: r[k],
        },
    ],
    'success_21_28_percent':
        results
            .where(
              (r) =>
                  int.parse(r['id'] as String) <= 28 &&
                  r['status'] == 'SUCCESS',
            )
            .length /
        8 *
        100,
    'success_29_30_percent':
        results
            .where(
              (r) =>
                  int.parse(r['id'] as String) >= 29 &&
                  r['status'] == 'SUCCESS',
            )
            .length /
        2 *
        100,
    'fastest': sorted.isEmpty
        ? null
        : {'id': sorted.first['id'], 'url': sorted.first['url']},
    'slowest': sorted.isEmpty
        ? null
        : {'id': sorted.last['id'], 'url': sorted.last['url']},
  };
  output.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'phase': 'B3.1',
      'started_at_utc': started,
      'finished_at_utc': DateTime.now().toUtc().toIso8601String(),
      'method':
          'Sequential, one attempt per URL, existing P0 extractor, desktop Dart JIT; no retries, no ground truth reads. Timing statistics include SUCCESS only; HTTP_ERROR times are separate. Extraction not run is 0ms. No retries or bypass.',
      'summary': summary,
      'results': results,
    }),
  );
  final md = StringBuffer('# B3.1 – batch 21–30\n\n$started\n\n');
  md.writeln(
    'Egy sorozatos kérés/URL; retry nincs. Desktop Dart JIT, nem mobilmérés. Ground truth összevetés nem történt. A teljes jelöltek és warnings a JSON-ban; HTML snapshotok későbbi offline P2-höz.\n',
  );
  md.writeln(
    '| ID | URL | Status | HTTP | Title | Ingredients | Instructions | JSON-LD | Candidates | Bytes | Fetch ms | Extract ms | Total ms | Warnings / error |',
  );
  md.writeln('|---|---|---|---|---|---|---|---|---|---|---|---|---|---|');
  String cell(Object? value) =>
      (value?.toString() ?? '—').replaceAll('|', r'\|').replaceAll('\n', ' ');
  for (final r in results) {
    md.writeln(
      '| ${['id', 'url', 'status', 'http_status', 'title', 'ingredient_count', 'instruction_count', 'json_ld_block_count', 'recipe_candidate_count', 'html_bytes', 'fetch_ms', 'extract_ms', 'total_ms'].map((k) => cell(r[k])).join(' | ')} | ${cell(r['warnings'])} ${cell(r['error'])} |',
    );
  }
  md.writeln(
    '\n## Összesítés\n\n```json\n${const JsonEncoder.withIndent('  ').convert(summary)}\n```',
  );
  md.writeln(
    '\nHTTP 403 = ACCESS / FETCH LIMITATION. Existing runner discards non-2xx body after counting bytes. No usable recipe HTML retained; JSON-LD presence is unexamined, extractor not executed. HTTP errors are excluded from success timing.\n',
  );
  md.writeln('\n## Snapshot comparison\n');
  for (final r in results) {
    md.writeln(
      '- ${r['id']}: ${r['snapshot_comparison']}; final URL: ${r['final_url']}',
    );
  }
  md.writeln(
    '\nDIFFERENT means HTML changed, not necessarily recipe content. B3.0 snapshots and ground truth are unchanged. B3.2 must reconcile snapshot versions.',
  );
  File(
    'results/b3_1_batch_21-30.md',
  ).writeAsStringSync('${md.toString().trimRight()}\n');
}
