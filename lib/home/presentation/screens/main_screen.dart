import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../features/auth/data/repositories/auth_repository.dart';
import '../../../recipes/presentation/screens/recipes_screen.dart';
import '../../../shopping/presentation/screens/shopping_screen.dart';
import '../../../what_to_cook/presentation/screens/what_to_cook_screen.dart';
import '../../../recipes/presentation/screens/add_recipe_screen.dart';
import '../../../shopping/data/repositories/shopping_repository.dart';
import '../../../shopping/presentation/widgets/shopping_item_dialog.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  final _authRepository = AuthRepository();
  final _shoppingRepository = ShoppingRepository();

  static const List<String> _titles = [
    'Receptek',
    'Bevásárlólista',
    'Mit főzzek?',
  ];

  int _recipesVersion = 0;

  List<Widget> get _screens => [
    RecipesScreen(key: ValueKey(_recipesVersion)),
    const ShoppingListScreen(),
    const WhatToCookScreen(),
  ];
  String _formatQuantity(num quantity) {
    final rounded = (quantity * 100).round() / 100;

    if (rounded % 1 == 0) {
      return rounded.toInt().toString();
    }

    return rounded
        .toStringAsFixed(2)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '')
        .replaceAll('.', ',');
  }
  ({num quantity, String unit}) _formatShoppingAmount(
      num quantity,
      String unit,
      ) {
    final normalizedUnit = unit.trim().toLowerCase();

    if (normalizedUnit == 'g' && quantity >= 1000) {
      return (
      quantity: quantity / 1000,
      unit: 'kg',
      );
    }

    if (normalizedUnit == 'ml' && quantity >= 1000) {
      return (
      quantity: quantity / 1000,
      unit: 'l',
      );
    }

    return (
    quantity: quantity,
    unit: unit,
    );
  }
  Future<void> _shareShoppingList() async {
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
      final formattedAmount = _formatShoppingAmount(
        item.quantity,
        item.unit,
      );

      buffer.writeln(
        '• ${item.name} – '
            '${_formatQuantity(formattedAmount.quantity)} '
            '${formattedAmount.unit}',
      );
    }
    buffer.writeln();
    buffer.writeln('──────────────');
    buffer.writeln('Készült a Kuktám alkalmazással');

    await SharePlus.instance.share(
      ShareParams(
        text: buffer.toString().trim(),
      ),
    );
  }
  Widget? _buildFloatingActionButton(BuildContext context) {
    switch (_selectedIndex) {
      case 0:
        return FloatingActionButton(
          onPressed: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => const AddRecipeScreen(),
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
          if (_selectedIndex == 1)
            IconButton(
              tooltip: 'Bevásárlólista megosztása',
              icon: const Icon(Icons.share_outlined),
              onPressed: _shareShoppingList,
            ),
          IconButton(
            tooltip: 'Profil',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () async {
              final selected = await showMenu<String>(
                context: context,
                position: const RelativeRect.fromLTRB(1000, 80, 16, 0),
                items: const [
                  PopupMenuItem(
                    value: 'logout',
                    child: Row(
                      children: [
                        Icon(Icons.logout),
                        SizedBox(width: 12),
                        Text('Kijelentkezés'),
                      ],
                    ),
                  ),
                ],
              );

              if (selected == 'logout') {
                await _authRepository.signOut();
              }
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