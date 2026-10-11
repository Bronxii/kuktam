import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/sharing/recipe_share_codec.dart';
import 'package:kuktam/recipes/domain/models/recipe.dart';

const sampleRecipe = Recipe(
  id: 'PRIVATE_DOC',
  name: 'Őszibarackos süti',
  ingredients: [
    RecipeIngredient(name: 'liszt', quantity: 1.234567890123, unit: 'kg'),
    RecipeIngredient(name: 'tojás', quantity: 2, unit: 'db'),
  ],
  spices: [
    RecipeSpice(name: 'só'),
    RecipeSpice(name: 'bors'),
  ],
  preparation: '\nKeverd össze.\n\nSüsd készre.\n',
);
Map<String, dynamic> payload() =>
    jsonDecode(utf8.decode(RecipeShareCodec.encode(sampleRecipe)))
        as Map<String, dynamic>;
void main() {
  test('escaped invalid Unicode and overflow numbers reject', () {
    final p = payload();
    p['recipe']['name'] = String.fromCharCode(0xd800);
    expect(
      () => RecipeShareCodec.decode(utf8.encode(jsonEncode(p))),
      throwsA(isA<RecipeShareFailure>()),
    );
    final valid = utf8.decode(RecipeShareCodec.encode(sampleRecipe));
    expect(
      () => RecipeShareCodec.decode(
        utf8.encode(valid.replaceFirst('1.234567890123', '1e400')),
      ),
      throwsA(isA<RecipeShareFailure>()),
    );
  });
  test(
    'exact allowlist and lossless domain to file to new draft roundtrip',
    () {
      final bytes = RecipeShareCodec.encode(sampleRecipe);
      final json = payload();
      expect(json.keys, ['format', 'version', 'recipe']);
      expect(json['recipe'].keys, [
        'name',
        'ingredients',
        'spices',
        'preparation',
      ]);
      expect(json['format'], 'kuktam.recipe');
      expect(json['version'], 1);
      expect(utf8.decode(bytes), endsWith('\n'));
      final result = RecipeShareCodec.decode(bytes);
      expect(result.id, isNull);
      expect(result.toMap(), sampleRecipe.toMap());
      for (final forbidden in [
        'PRIVATE_DOC',
        'uid',
        'email',
        'createdAt',
        'updatedAt',
        'billing',
        'entitlement',
        'purchaseToken',
        'device',
        'accountLifecycle',
        'HMAC',
      ]) {
        expect(utf8.decode(bytes), isNot(contains(forbidden)));
      }
    },
  );
  test('filename safety, Unicode, extension and custom MIME', () {
    expect(
      RecipeShareCodec.filename('../Árvíz:*/x'),
      '.._Árvíz___x.kuktamrecipe',
    );
    expect(RecipeShareCodec.mime, 'application/vnd.kuktam.recipe+json');
    expect(RecipeShareCodec.filename(''), 'Recept.kuktamrecipe');
    expect(
      utf8.encode(RecipeShareCodec.filename('ő' * 300)).length,
      lessThan(140),
    );
  });
  final mutations = <String, void Function(Map<String, dynamic>)>{
    'wrong format': (p) => p['format'] = 'kuktam.recipes',
    'version 0': (p) => p['version'] = 0,
    'future': (p) => p['version'] = 2,
    'version double': (p) => p['version'] = 1.0,
    'missing recipe': (p) => p.remove('recipe'),
    'missing name': (p) => (p['recipe'] as Map).remove('name'),
    'wrong ingredients': (p) => p['recipe']['ingredients'] = {},
    'wrong quantity': (p) => p['recipe']['ingredients'][0]['quantity'] = '1',
    'zero': (p) => p['recipe']['ingredients'][0]['quantity'] = 0,
    'negative': (p) => p['recipe']['ingredients'][0]['quantity'] = -1,
    'unknown unit': (p) => p['recipe']['ingredients'][0]['unit'] = 'dkg',
    'bad spice': (p) => p['recipe']['spices'][0] = 'só',
    'empty spice': (p) => p['recipe']['spices'][0]['name'] = ' ',
    'extra field': (p) => p['recipe']['uid'] = 'PRIVATE',
    'extra envelope': (p) => p['owner'] = {},
  };
  for (final entry in mutations.entries) {
    test('strict reject ${entry.key}', () {
      final p = payload();
      entry.value(p);
      expect(
        () => RecipeShareCodec.decode(utf8.encode(jsonEncode(p))),
        throwsA(isA<RecipeShareFailure>()),
      );
    });
  }
  for (final text in [
    '{bad',
    '[]',
    '{"format":"kuktam.recipe","version":1,"recipe":NaN}',
    '[' * 30 + ']' * 30,
  ]) {
    test(
      'malformed or deep input safely rejected $text',
      () => expect(
        () => RecipeShareCodec.decode(utf8.encode(text)),
        throwsA(isA<RecipeShareFailure>()),
      ),
    );
  }
  test('invalid UTF8 and size boundaries', () {
    expect(
      () => RecipeShareCodec.decode([0xc3, 0x28]),
      throwsA(isA<RecipeShareFailure>()),
    );
    final bytes = RecipeShareCodec.encode(sampleRecipe);
    final exact = [
      ...bytes,
      ...List.filled(RecipeShareCodec.maxBytes - bytes.length, 32),
    ];
    expect(RecipeShareCodec.decode(exact).name, sampleRecipe.name);
    expect(
      () => RecipeShareCodec.decode([...exact, 32]),
      throwsA(isA<RecipeShareFailure>().having((e) => e.code, 'code', 'size')),
    );
  });
  for (final q in [double.nan, double.infinity, -1.0, 0.0]) {
    test(
      'outbound invalid quantity $q controlled',
      () => expect(
        () => RecipeShareCodec.encode(
          Recipe(
            name: 'x',
            ingredients: [RecipeIngredient(name: 'x', quantity: q, unit: 'g')],
            spices: [],
            preparation: '',
          ),
        ),
        throwsA(isA<RecipeShareFailure>()),
      ),
    );
  }
  test('legacy empty spice controlled error without persisted mutation', () {
    const recipe = Recipe(
      name: 'x',
      ingredients: [],
      spices: [RecipeSpice(name: '')],
      preparation: '',
    );
    expect(
      () => RecipeShareCodec.encode(recipe),
      throwsA(isA<RecipeShareFailure>()),
    );
    expect(recipe.spices.single.name, '');
  });
  test('unknown version has friendly version error', () {
    final p = payload()..['version'] = 99;
    expect(
      () => RecipeShareCodec.decode(utf8.encode(jsonEncode(p))),
      throwsA(
        isA<RecipeShareFailure>().having((e) => e.code, 'code', 'version'),
      ),
    );
  });
}
