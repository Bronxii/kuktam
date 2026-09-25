import 'dart:convert';
import 'dart:io';
import 'package:kuktam_web_import_poc/runner.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1 || !args.single.startsWith(RegExp(r'https?://'))) {
    stderr.writeln(
      'Usage: dart run bin/extract.dart https://example.com/recipe',
    );
    exitCode = 64;
    return;
  }
  final result = await runUrl(args.single);
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
}
