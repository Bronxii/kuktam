import 'package:flutter/material.dart';
import '../../../features/auth/data/repositories/auth_repository.dart';

import '../../../recipes/presentation/screens/recipes_screen.dart';
import '../../../shopping/presentation/screens/shopping_screen.dart';
import '../../../what_to_cook/presentation/screens/what_to_cook_screen.dart';
import '../../../recipes/presentation/screens/add_recipe_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  final _authRepository = AuthRepository();

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_selectedIndex]),
        actions: [
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
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton(onPressed: () async {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => const AddRecipeScreen(),
          ),
        );

        setState(() {
          _recipesVersion++;
        });
      },
        tooltip: 'Új recept',
        child: const Icon(Icons.add),
      )
          : null,
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