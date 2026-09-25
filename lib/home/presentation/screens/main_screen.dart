import '../../../recipes/data/services/web_recipe_fetcher.dart';
import '../../../recipes/domain/models/web_recipe_import_handoff.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../../shopping/domain/shopping_quantity_formatter.dart';

import '../../../recipes/presentation/screens/recipes_screen.dart';
import '../../../shopping/presentation/screens/shopping_screen.dart';
import '../../../what_to_cook/presentation/screens/what_to_cook_screen.dart';
import '../../../recipes/presentation/screens/add_recipe_screen.dart';
import '../../../shopping/data/repositories/shopping_repository.dart';
import '../../../shopping/presentation/widgets/shopping_item_dialog.dart';
import '../../../shopping/presentation/widgets/shopping_import_dialog.dart';
import '../../../settings/settings_screen.dart';
import '../../../recipes/presentation/widgets/recipe_import_dialog.dart';
import '../../../recipes/data/repositories/recipe_repository.dart';
import '../../../recipes/domain/models/recipe.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key, this.tabBodies, this.recipeRepository, this.shoppingRepository, this.importWeb})
      : assert(tabBodies == null || tabBodies.length == 3);

  // Optional dependencies keep navigation tests independent of Firebase.
  final List<Widget>? tabBodies;
  final WebImportAction? importWeb;
  final RecipeRepository? recipeRepository;
  final ShoppingRepository? shoppingRepository;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  late final _shoppingRepository = widget.shoppingRepository ?? ShoppingRepository();

  static const List<String> _titles = [
    'Receptek',
    'Bevásárlólista',
    'Mit főzzek?',
  ];

  int _recipesVersion = 0;
  bool _importingRecipe = false;
  final _importLifetime = WebImportCancellation();
  @override
  void dispose() {
    _importLifetime.cancel();
    super.dispose();
  }

  Future<void> _importRecipe() async {
    if (_importingRecipe) return;
    _importingRecipe = true;
    try {
      final draft = await showRecipeImportDialog(context, lifetime: _importLifetime, importWeb: widget.importWeb);
      if (!mounted || draft == null) return;
      final saved = await Navigator.of(context).push<Recipe>(
        MaterialPageRoute<Recipe>(
          builder: (_) => AddRecipeScreen(
            initialImport: draft,
            webImport: draft is WebRecipeImportHandoff ? draft : null,
            recipeRepository: widget.recipeRepository,
          ),
        ),
      );
      if (mounted && saved != null) {
        setState(() => _recipesVersion++);
      }
    } finally {
      _importingRecipe = false;
    }
  }

  List<Widget> get _screens => widget.tabBodies ?? [
    RecipesScreen(key: ValueKey(_recipesVersion), recipeRepository: widget.recipeRepository),
    ShoppingListScreen(shoppingRepository: _shoppingRepository),
    WhatToCookScreen(recipeRepository: widget.recipeRepository),
  ];
  bool _sharingShopping = false;
  Future<void> _shareShoppingList() async {
    if (_sharingShopping) return;
    _sharingShopping = true;
    try {
    final items = await _shoppingRepository.watchShoppingItems().first;

    if (!mounted) {
      return;
    }

    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A bevásárlólista üres.'),
        ),
      );
      return;
    }

    final buffer = StringBuffer();

    buffer.writeln('Bevásárlólista:');
    buffer.writeln();

    for (final item in items) {
      buffer.writeln('• ${item.name} – ${formatShoppingAmount(item.quantity, item.unit)}');
    }
    buffer.writeln();
    buffer.writeln('──────────────');
    buffer.writeln('Készült a Kuktám alkalmazással');

    await SharePlus.instance.share(
      ShareParams(
        text: buffer.toString().trim(),
      ),
    );
    } catch (_) {
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Nem sikerült megosztani a bevásárlólistát. Próbáld újra.'),
      )); }
    } finally {
      _sharingShopping = false;
    }
  }
  Widget? _buildFloatingActionButton(BuildContext context) {
    switch (_selectedIndex) {
      case 0:
        return FloatingActionButton(
          onPressed: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => AddRecipeScreen(recipeRepository: widget.recipeRepository),
              ),
            );

            if (!mounted) {
              return;
            }

            setState(() {
              _recipesVersion++;
            });
          },
          tooltip: 'Új recept',
          child: const Icon(Icons.add),
        );

      case 1:
        return FloatingActionButton(
          onPressed: () {
            showShoppingItemDialog(
              context: context,
              shoppingRepository: _shoppingRepository,
            );
          },
          tooltip: 'Új tétel',
          child: const Icon(Icons.add),
        );

      case 2:
        return null;

      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_selectedIndex]),
        actions: [
          if (_selectedIndex == 0)
            IconButton(
              tooltip: 'Recept importálása',
              icon: const Icon(Icons.file_download_outlined),
              onPressed: _importRecipe,
            ),
          if (_selectedIndex == 1)
            IconButton(
              tooltip: 'Importálás',
              icon: const Icon(Icons.file_download_outlined),
              onPressed: () => showShoppingImportDialog(context),
            ),
          if (_selectedIndex == 1)
            IconButton(
              tooltip: 'Bevásárlólista megosztása',
              icon: const Icon(Icons.share_outlined),
              onPressed: _shareShoppingList,
            ),
          IconButton(
            tooltip: 'Profil és beállítások',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => SettingsScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      floatingActionButton: _buildFloatingActionButton(context),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (int index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: 'Receptek',
          ),
          NavigationDestination(
            icon: Icon(Icons.shopping_cart_outlined),
            selectedIcon: Icon(Icons.shopping_cart),
            label: 'Lista',
          ),
          NavigationDestination(
            icon: Icon(Icons.restaurant_menu_outlined),
            selectedIcon: Icon(Icons.restaurant_menu),
            label: 'Mit főzzek?',
          ),
        ],
      ),
    );
  }
}
