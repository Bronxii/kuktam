import 'package:flutter/material.dart';
import '../../../sharing/text_share_controller.dart';
import '../../../sharing/recipe_file_receiver.dart';
import '../../../sharing/shared_recipe_text_normalizer.dart';
import '../../../pro/feature_gate.dart';
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
  const MainScreen({
    super.key,
    this.tabBodies,
    this.textShares,
    this.recipeFiles,
    this.shareNavigation,
    this.recipeRepository,
    this.shoppingRepository,
  }) : assert(tabBodies == null || tabBodies.length == 3);

  // Optional dependencies keep navigation tests independent of Firebase.
  final List<Widget>? tabBodies;
  final TextShareController? textShares;
  final RecipeFileReceiver? recipeFiles;
  final TextShareNavigationObserver? shareNavigation;
  final RecipeRepository? recipeRepository;
  final ShoppingRepository? shoppingRepository;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  late final _textShares = widget.textShares ?? TextShareController.instance;
  late final _shareNavigation = widget.shareNavigation ?? textShareNavigation;
  late final _recipeFiles = widget.recipeFiles ?? RecipeFileReceiver.instance;
  bool _shareScheduled = false;

  @override
  void initState() {
    super.initState();
    _textShares.addListener(_scheduleShare);
    _recipeFiles.addListener(_scheduleShare);
    _shareNavigation.changes.addListener(_scheduleShare);
    WidgetsBinding.instance.addObserver(this);
    _scheduleShare();
  }

  @override
  void dispose() {
    _textShares.removeListener(_scheduleShare);
    _recipeFiles.removeListener(_scheduleShare);
    _shareNavigation.changes.removeListener(_scheduleShare);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _scheduleShare();
  }

  void _scheduleShare() {
    if (!mounted || _shareScheduled || !(_textShares.hasPending || _recipeFiles.hasPending)) return;
    _shareScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _shareScheduled = false;
      if (!mounted ||
          _importingRecipe ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
      if (_recipeFiles.hasPending) {
        final notice = _recipeFiles.takeNotice();
        if (notice != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(notice)));
        final recipe = _recipeFiles.take();
        if (recipe != null) { _importStructured(recipe); } else { _scheduleShare(); }
        return;
      }
      final notice = _textShares.takeNotice();
      if (notice != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(notice)));
      }
      final text = _textShares.take();
      if (text == null) return;
      if (TextShareController.isUrlOnly(text)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'A Kuktám megosztott szöveget fogad. Jelöld ki és oszd meg a recept szövegét a hivatkozás helyett.',
            ),
          ),
        );
        _scheduleShare();
        return;
      }
      _importRecipe(
        initialText: const SharedRecipeTextNormalizer().normalize(text),
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _importStructured(Recipe recipe) async {
    _importingRecipe = true;
    final generation = _recipeFiles.generation;
    try {
      final saved = await Navigator.of(context).push<Recipe>(MaterialPageRoute<Recipe>(
        builder: (_) => AddRecipeScreen(initialRecipe: recipe,
          validateSession: () => _recipeFiles.check(generation),
          recipeRepository: widget.recipeRepository),
      ));
      if (mounted && saved != null) setState(() => _recipesVersion++);
    } finally { _importingRecipe = false; _scheduleShare(); }
  }

  int _selectedIndex = 0;

  late final _shoppingRepository =
      widget.shoppingRepository ?? ShoppingRepository();

  static const List<String> _titles = [
    'Receptek',
    'Bevásárlólista',
    'Mit főzzek?',
  ];

  int _recipesVersion = 0;
  bool _importingRecipe = false;

  Future<void> _importRecipe({String? initialText}) async {
    if (_importingRecipe) return;
    _importingRecipe = true;
    try {
      final draft = await showRecipeImportDialog(
        context,
        initialText: initialText,
      );
      if (!mounted || draft == null) return;
      final saved = await Navigator.of(context).push<Recipe>(
        MaterialPageRoute<Recipe>(
          builder: (_) => AddRecipeScreen(
            initialImport: draft,
            recipeRepository: widget.recipeRepository,
          ),
        ),
      );
      if (mounted && saved != null) {
        setState(() => _recipesVersion++);
      }
    } finally {
      _importingRecipe = false;
      _scheduleShare();
    }
  }

  List<Widget> get _screens =>
      widget.tabBodies ??
      [
        RecipesScreen(
          key: ValueKey(_recipesVersion),
          recipeRepository: widget.recipeRepository,
        ),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('A bevásárlólista üres.')));
        return;
      }

      final buffer = StringBuffer();

      buffer.writeln('Bevásárlólista:');
      buffer.writeln();

      for (final item in items) {
        buffer.writeln(
          '• ${item.name} – ${formatShoppingAmount(item.quantity, item.unit)}',
        );
      }
      buffer.writeln();
      buffer.writeln('──────────────');
      buffer.writeln('Készült a Kuktám alkalmazással');

      await SharePlus.instance.share(
        ShareParams(text: buffer.toString().trim()),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Nem sikerült megosztani a bevásárlólistát. Próbáld újra.',
            ),
          ),
        );
      }
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
                builder: (context) =>
                    AddRecipeScreen(recipeRepository: widget.recipeRepository),
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
                MaterialPageRoute<void>(builder: (context) => SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: IndexedStack(index: _selectedIndex, children: _screens),
      floatingActionButton: _buildFloatingActionButton(context),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (int index) async {
          if (index == 2 &&
              (!await FeatureGate.request(context, ProFeature.whatToCook) ||
                  !mounted)) {
            return;
          }
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
            icon: ProFeatureIcon(
              feature: ProFeature.whatToCook,
              icon: Icons.restaurant_menu_outlined,
            ),
            selectedIcon: Icon(Icons.restaurant_menu),
            label: 'Mit főzzek?',
          ),
        ],
      ),
    );
  }
}
