import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/recipes/domain/models/recipe.dart';
import 'package:kuktam/recipes/presentation/screens/recipe_details_screen.dart';
import 'package:kuktam/what_to_cook/presentation/screens/what_to_cook_screen.dart';
import 'package:kuktam/features/auth/data/repositories/auth_repository.dart';
import 'package:kuktam/features/auth/presentation/widgets/auth_gate.dart';
import '../recipes/recipe_core_test.dart' show CoreRepository;
import '../recipes/recipe_repository_test.dart'
    show RecipeTestAuth, RecipeTestUser;
import 'recipe_matcher_test.dart' show recipe;

class CookRepository extends CoreRepository {
  final events = StreamController<List<Recipe>>.broadcast();
  bool wait = false;
  @override
  Stream<List<Recipe>> watchRecipes() async* {
    if (!wait) yield List.of(recipes);
    yield* events.stream;
  }
}

Future<void> add(WidgetTester tester, String name) async {
  await tester.enterText(find.byType(TextField), name);
  await tester.pump();
  await tester.tap(find.byTooltip('Alapanyag hozzáadása'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'empty input browse, exact subset, extra pantry, duplicate, remove, detail/back and live recipe edits',
    (tester) async {
      final repo = CookRepository()
        ..recipes.addAll([
          recipe('A étel', ['tojás', 'liszt']),
          recipe('B étel', ['tojás', 'liszt', 'tej']),
        ]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: WhatToCookScreen(recipeRepository: repo)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Összes recept (2)'), findsOneWidget);
      await add(tester, 'Tojás');
      expect(find.text('Nincs megfelelő recept'), findsOneWidget);
      await add(tester, ' LISZT ');
      expect(find.text('A étel'), findsOneWidget);
      expect(find.text('B étel'), findsNothing);
      await add(tester, 'alma');
      expect(find.text('A étel'), findsOneWidget);
      await add(tester, 'tojás');
      expect(find.byType(InputChip), findsNWidgets(3));
      await tester.tap(find.text('A étel'));
      await tester.pumpAndSettle();
      expect(find.byType(RecipeDetailsScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(InputChip), findsNWidgets(3));
      await add(tester, 'tej');
      expect(find.text('Találatok (2)'), findsOneWidget);
      repo.events.add([
        recipe('B új', ['tej']),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('A étel'), findsNothing);
      expect(find.text('B új'), findsOneWidget);
      await tester.tap(find.byTooltip('tej eltávolítása'));
      await tester.pumpAndSettle();
      expect(find.text('Nincs megfelelő recept'), findsOneWidget);
      repo.events.add([]);
      await tester.pumpAndSettle();
      expect(find.text('Még nincsenek receptjeid'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await repo.events.close();
    },
  );
  testWidgets(
    'load errors hide technical details and later stream data recovers',
    (tester) async {
      final repo = CookRepository()..wait = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: WhatToCookScreen(recipeRepository: repo)),
        ),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      repo.events.addError(StateError('private Firebase trace'));
      await tester.pumpAndSettle();
      expect(find.textContaining('private Firebase'), findsNothing);
      expect(find.text('Nem sikerült betölteni a recepteket.'), findsOneWidget);
      repo.events.add([
        recipe('Leves', ['víz']),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Leves'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await repo.events.close();
    },
  );
  testWidgets(
    'AuthGate user switch clears pantry and cancels prior recipe stream',
    (tester) async {
      final auth = RecipeTestAuth();
      final a = CookRepository()..recipes.add(recipe('A titkos', ['tojás']));
      final b = CookRepository()..recipes.add(recipe('B saját', ['liszt']));
      await tester.pumpWidget(
        MaterialApp(
          home: AuthGate(
            authRepository: AuthRepository(firebaseAuth: auth),
            mainBuilder: (_) => Scaffold(
              body: WhatToCookScreen(
                recipeRepository: auth.currentUser!.uid == 'A' ? a : b,
              ),
            ),
          ),
        ),
      );
      auth.changes.add(auth.currentUser);
      await tester.pumpAndSettle();
      await add(tester, 'tojás');
      expect(find.text('A titkos'), findsOneWidget);
      auth.currentUser = RecipeTestUser('B');
      auth.changes.add(auth.currentUser);
      await tester.pumpAndSettle();
      a.events.add([
        recipe('A késői', ['tojás']),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('A titkos'), findsNothing);
      expect(find.text('A késői'), findsNothing);
      expect(find.text('B saját'), findsOneWidget);
      expect(find.byType(InputChip), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await auth.changes.close();
      await a.events.close();
      await b.events.close();
    },
  );
}
