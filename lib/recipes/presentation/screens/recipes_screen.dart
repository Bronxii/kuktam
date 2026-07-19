import 'package:flutter/material.dart';

import 'package:kuktam/recipes/data/repositories/recipe_repository.dart';
import 'package:kuktam/recipes/domain/models/recipe.dart';
import 'package:kuktam/recipes/presentation/screens/recipe_details_screen.dart';

class RecipesScreen extends StatefulWidget {
  const RecipesScreen({super.key});

  @override
  State<RecipesScreen> createState() => _RecipesScreenState();
}
class _RecipesScreenState extends State<RecipesScreen> {
  final RecipeRepository _recipeRepository = RecipeRepository();

  late Future<List<Recipe>> _recipesFuture;

  @override
  void initState() {
    super.initState();
    _recipesFuture = _recipeRepository.getRecipes();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SearchBar(
            hintText: 'Recept keresése...',
            leading: Icon(Icons.search),
          ),
          const SizedBox(height: 32),
Expanded(
child: FutureBuilder<List<Recipe>>(
future: _recipesFuture,
builder: (context, snapshot) {
if (snapshot.connectionState == ConnectionState.waiting) {
return const Center(
child: CircularProgressIndicator(),
);
}

if (snapshot.hasError) {
return Center(
child: Text('Hiba: ${snapshot.error}'),
);
}

final recipes = snapshot.data ?? [];

if (recipes.isEmpty) {
return Center(
child: Column(
mainAxisSize: MainAxisSize.min,
children: [
Icon(
Icons.menu_book_rounded,
size: 72,
color: Theme.of(context).colorScheme.primary,
),
const SizedBox(height: 16),
Text(
'Még nincsenek receptjeid',
style: Theme.of(context).textTheme.titleLarge,
),
const SizedBox(height: 8),
const Text(
'Az első recept hozzáadásához nyomd meg a + gombot.',
textAlign: TextAlign.center,
),
],
),
);
}

return ListView.builder(
itemCount: recipes.length,
itemBuilder: (context, index) {
final recipe = recipes[index];

return Card(
  child: ListTile(
    leading: const Icon(Icons.restaurant_menu),
    title: Text(recipe.name),
    trailing: const Icon(Icons.chevron_right),
    onTap: () {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => RecipeDetailsScreen(
            recipe: recipe,
          ),
        ),
      );
    },
  ),
);
},
);
},
),
),
        ],
      ),
    );
  }
}