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
  if (args.length != 1 || args.single != '--run-batch-11-20') {
    stderr.writeln('Explicit approval required: --run-batch-11-20');
    exitCode = 64;
    return;
  }
  final directory = Directory('results');
  await directory.create(recursive: true);
  final output = File('results/b2_1_batch_11-20.json');
  final journal = File('results/b2_1_batch_11-20.jsonl');
  if (output.existsSync() || journal.existsSync()) {
    throw StateError(
      'Existing results: refusing accidental repeated requests.',
    );
  }
  // Validate every authorized URL before making any network request.
  final inputs = <({String id, String url})>[];
  for (var i = 11; i <= 20; i++) {
    final id = i.toString().padLeft(2, '0');
    final url = File(
      '../../test/fixtures/web_import_corpus/batch_2_11-20/website_$id.txt',
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
          ? 'b2_1_html/source_${input.id}.html'
          : null,
    };
    // Snapshot/report I/O is outside the measured URL pipeline.
    if (captured?.body.isNotEmpty == true) {
      Directory('results/b2_1_html').createSync(recursive: true);
      File(
        'results/b2_1_html/source_${input.id}.html',
      ).writeAsStringSync(captured!.body);
    }
    final previous = File('results/b2_0_sources/source_${input.id}.html');
    record['snapshot_comparison'] = {
      'b2_0_snapshot': 'b2_0_sources/source_${input.id}.html',
      'method':
          'Exact decoded HTML string equality, no recipe content comparison',
      'status': captured?.body.isNotEmpty != true || !previous.existsSync()
          ? 'UNAVAILABLE'
          : previous.readAsStringSync() == captured!.body
          ? 'IDENTICAL'
          : 'DIFFERENT',
      'b2_0_snapshot_bytes': previous.existsSync()
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
  final sorted = [...results]
    ..sort(
      (a, b) => (a['total_ms'] as double).compareTo(b['total_ms'] as double),
    );
  final summary = {
    'total_urls': 10,
    'domains': {
      for (final domain in results.map((r) => r['domain'] as String).toSet())
        domain: {
          'total': results.where((r) => r['domain'] == domain).length,
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
      key: stats(results.map((r) => r[key] as double).toList()),
    'fastest': {'id': sorted.first['id'], 'url': sorted.first['url']},
    'slowest': {'id': sorted.last['id'], 'url': sorted.last['url']},
  };
  output.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'phase': 'B2.1',
      'started_at_utc': started,
      'finished_at_utc': DateTime.now().toUtc().toIso8601String(),
      'method':
          'Sequential, one attempt per URL, existing P0 extractor, desktop Dart JIT; no retries, no ground truth reads. Statistics include all ten outcomes; extraction not run is 0ms.',
      'summary': summary,
      'results': results,
    }),
  );
  final md = StringBuffer('# B2.1 – batch 11–20\n\n$started\n\n');
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
  md.writeln('\n## Snapshot comparison\n');
  for (final r in results) {
    md.writeln(
      '- ${r['id']}: ${r['snapshot_comparison']}; final URL: ${r['final_url']}',
    );
  }
  md.writeln(
    '\nDIFFERENT means HTML changed, not necessarily recipe content. B2.0 snapshots and ground truth are unchanged. B2.2 must reconcile snapshot versions.',
  );
  File(
    'results/b2_1_batch_11-20.md',
  ).writeAsStringSync('${md.toString().trimRight()}\n');
}
