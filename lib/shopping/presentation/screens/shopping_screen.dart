import 'package:flutter/material.dart';

import '../../data/repositories/shopping_repository.dart';
import '../widgets/shopping_item_tile.dart';
import '../widgets/shopping_item_dialog.dart';

class ShoppingListScreen extends StatelessWidget {
  const ShoppingListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final shoppingRepository = ShoppingRepository();

    return StreamBuilder(
      stream: shoppingRepository.watchShoppingItems(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        if (snapshot.hasError) {
          return const Center(
            child: Text('Nem sikerült betölteni a bevásárlólistát.'),
          );
        }

        final items = snapshot.data ?? [];

        if (items.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.shopping_cart_outlined,
                  size: 72,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'A bevásárlólistád üres!',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'A recepted hozzávalóit később egyetlen gombbal ide tudod majd tenni.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: items.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final item = items[index];

            return ShoppingItemTile(
              item: item,
              onItemTap: () {},
              onItemLongPress: () async {
                await showModalBottomSheet(
                  context: context,
                  builder: (sheetContext) {
                    return SafeArea(
                      child: Wrap(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.edit_outlined),
                            title: const Text('Szerkesztés'),
                            onTap: () {
                              Navigator.pop(sheetContext);

                              showShoppingItemDialog(
                                context: context,
                                item: item,
                                shoppingRepository: shoppingRepository,
                              );
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.delete_outline),
                            title: const Text('Törlés'),
                            onTap: () async {
                              Navigator.pop(sheetContext);

                              final shouldDelete = await showDialog<bool>(
                                context: context,
                                builder: (dialogContext) {
                                  return AlertDialog(
                                    title: const Text('Tétel törlése'),
                                    content: Text(
                                      'Biztosan törölni szeretnéd ezt a tételt?\n\n${item.name}',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(dialogContext, false);
                                        },
                                        child: const Text('Mégse'),
                                      ),
                                      FilledButton(
                                        onPressed: () {
                                          Navigator.pop(dialogContext, true);
                                        },
                                        child: const Text('Törlés'),
                                      ),
                                    ],
                                  );
                                },
                              );

                              if (shouldDelete != true) {
                                return;
                              }

                              await shoppingRepository.deleteItem(item.id);
                            },
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
              onCheckedChanged: () {
                shoppingRepository.setItemChecked(
                  id: item.id,
                  isChecked: !item.isChecked,
                );
              },
            );
          },
        );
      },
    );
  }
}