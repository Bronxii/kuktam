import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import '../bin/e2e_simulation.dart';

void main() {
  test('suffix removal requires exact suffix and matching domain', () {
    expect(
      displayTitle(
        'Süti | Mindmegette.hu',
        'https://www.mindmegette.hu/recept/suti',
      ),
      'Süti',
    );
    expect(
      displayTitle('Süti | Mindmegette.hu', 'https://other.test'),
      'Süti | Mindmegette.hu',
    );
    expect(
      displayTitle('Süti | Más oldal', 'https://mindmegette.hu'),
      'Süti | Más oldal',
    );
    expect(
      displayTitle('Mindmegette.hu süti', 'https://mindmegette.hu'),
      'Mindmegette.hu süti',
    );
  });
  test(
    'step labels join body, sections and orphan headings survive in order',
    () {
      expect(
        instructionLines([
          {'kind': 'section', 'text': 'Tészta'},
          {'kind': 'heading', 'text': 'Előkészítés'},
          {'kind': 'step', 'text': 'Keverd&nbsp;össze.'},
          {'kind': 'section', 'text': 'Máz'},
          {'kind': 'heading', 'text': 'Olvaszd fel.'},
          {'kind': 'step', 'text': 'Olvaszd fel.'},
          {'kind': 'heading', 'text': 'Tálalás'},
        ]),
        [
          'Tészta',
          'Előkészítés: Keverd össze.',
          'Máz',
          'Olvaszd fel.',
          'Tálalás',
        ],
      );
    },
  );
  test('display decoding preserves literal text and actual line breaks', () {
    expect(displayText('A&nbsp;B\r\nC &amp; D'), 'A B\nC & D');
    expect(displayText(r'A\r\nB'), r'A\r\nB');
    expect(displayText('2 < 3'), '2 < 3');
  });
  test(
    'full draft preserves raw input, invalid quantity, empty spices, no mutation',
    () {
      final c = <String, dynamic>{
        'title': 'Recept',
        'ingredients': ['0 g Cukor', '1 csipet Só'],
        'instructions': [
          {'kind': 'step', 'text': 'Keverd össze.'},
        ],
      };
      final before = jsonEncode(c);
      final result = simulate(c, 'https://example.test');
      final draft = result['draft']! as Map<String, Object?>;
      final rows = (draft['ingredients']! as List).cast<Map<String, Object?>>();
      expect(rows[0]['quantity'], isNull);
      expect(rows[0]['warnings'], contains('invalidQuantity'));
      expect(rows[1]['warnings'], contains('unknownUnit'));
      expect(rows[1]['canonical_unit'], 'db');
      expect(rows[0]['rawText'], '0 g Cukor');
      expect(rows[0]['sourceOrder'], 3);
      expect(draft['spices'], isEmpty);
      expect(draft['preparation'], 'Keverd össze.');
      expect(jsonEncode(c), before);
    },
  );
  test(
    'all ten saved inputs preserve every instruction body and 100 raw rows',
    () {
      final p1 =
          jsonDecode(File('results/p1_batch_01-10.json').readAsStringSync())
              as Map<String, dynamic>;
      var rows = 0;
      var steps = 0;
      for (final r in (p1['results'] as List).cast<Map<String, dynamic>>()) {
        final c = (r['candidates'] as List).single as Map<String, dynamic>;
        final result = simulate(c, r['url'] as String);
        final draft = result['draft']! as Map<String, Object?>;
        final ingredients = (draft['ingredients']! as List)
            .cast<Map<String, Object?>>();
        expect(ingredients.map((i) => i['rawText']).toList(), c['ingredients']);
        expect(draft['title'], result['normalized_title']);
        expect(draft['unprocessedSegments'], isEmpty);
        rows += ingredients.length;
        var offset = 0;
        for (final e
            in (c['instructions'] as List).cast<Map<String, dynamic>>().where(
              (e) => e['kind'] == 'step',
            )) {
          final body = displayText(e['text'] as String);
          final index = (draft['preparation']! as String).indexOf(body, offset);
          expect(index, greaterThanOrEqualTo(offset));
          offset = index + body.length;
          steps++;
        }
      }
      expect(rows, 100);
      expect(steps, 56);
    },
  );
}
