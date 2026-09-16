import 'package:flutter/material.dart';

import '../../domain/models/shopping_item.dart';
import '../../data/repositories/shopping_repository.dart';
import '../widgets/shopping_item_dialog.dart';
import '../widgets/shopping_item_tile.dart';

class ShoppingListScreen extends StatefulWidget {
  const ShoppingListScreen({super.key, this.shoppingRepository});
  final ShoppingRepository? shoppingRepository;
  @override
  State<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends State<ShoppingListScreen> {
  late final shoppingRepository = widget.shoppingRepository ?? ShoppingRepository();
  late Stream<List<ShoppingItem>> _items = shoppingRepository.watchShoppingItems();
  bool _busy = false;
  bool _confirming = false;

  Future<void> _write(Future<void> Function() action) async {
    if (_busy || !mounted) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Nem sikerült módosítani a bevásárlólistát. Próbáld újra.'),
      )); }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {


    return PopScope(
      canPop: !_busy,
      child: AbsorbPointer(absorbing: _busy, child: StreamBuilder<List<ShoppingItem>>(
      stream: _items,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        if (snapshot.hasError) {
          return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Nem sikerült betölteni a bevásárlólistát.'),
            TextButton(onPressed: () => setState(() => _items = shoppingRepository.watchShoppingItems()), child: const Text('Újra')),
          ]));
        }

        final items = snapshot.data ?? [];

        Future<void> finishShopping() async {
          if (_busy || _confirming) return;
          _confirming = true;
          var answered = false;
          final shouldFinish = await showDialog<bool>(
            context: context,
            builder: (dialogContext) {
              return AlertDialog(
                title: const Text('Bevásárlás befejezése'),
                content: const Text(
                  'Biztosan befejezed a bevásárlást?\n\n'
                      'A teljes bevásárlólista törlődni fog.',
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      if (answered) return;
                                answered = true;
                                Navigator.of(dialogContext).pop(false);
                    },
                    child: const Text('Mégsem'),
                  ),
                  FilledButton(
                    onPressed: () {
                      if (answered) return;
                                answered = true;
                                Navigator.of(dialogContext).pop(true);
                    },
                    child: const Text('Befejezés'),
                  ),
                ],
              );
            },
          );

          _confirming = false;
          if (!mounted || shouldFinish != true) {
            return;
          }

          await _write(shoppingRepository.clearShoppingList);
        }

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

        return Column(
          children: [
            if (_busy) const LinearProgressIndicator(),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: items.length,
                separatorBuilder: (context, index) =>
                const Divider(height: 1),
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
                                      shoppingRepository:
                                      shoppingRepository,
                                    );
                                  },
                                ),
                                ListTile(
                                  leading: const Icon(Icons.delete_outline),
                                  title: const Text('Törlés'),
                                  onTap: () async {
                                    Navigator.pop(sheetContext);

                                    if (_busy || _confirming) return;
                                    _confirming = true;
          var answered = false;
                                    final shouldDelete =
                                    await showDialog<bool>(
                                      context: context,
                                      builder: (dialogContext) {
                                        return AlertDialog(
                                          title: const Text(
                                            'Tétel törlése',
                                          ),
                                          content: Text(
                                            'Biztosan törölni szeretnéd ezt a tételt?\n\n${item.name}',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () {
                                                if (answered) return;
                                                answered = true;
                                                Navigator.pop(
                                                  dialogContext,
                                                  false,
                                                );
                                              },
                                              child:
                                              const Text('Mégse'),
                                            ),
                                            FilledButton(
                                              onPressed: () {
                                                if (answered) return;
                                                answered = true;
                                                Navigator.pop(
                                                  dialogContext,
                                                  true,
                                                );
                                              },
                                              child:
                                              const Text('Törlés'),
                                            ),
                                          ],
                                        );
                                      },
                                    );

                                    _confirming = false;
                                    if (!mounted || shouldDelete != true) {
                                      return;
                                    }

                                    await _write(() => shoppingRepository.deleteItem(item.id));
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                    onCheckedChanged: () {
                      _write(() => shoppingRepository.setItemChecked(
                        id: item.id,
                        isChecked: !item.isChecked,
                      ));
                    },
                  );
                },
              ),
            ),
            Padding(
              padding:
              const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: finishShopping,
                  icon: const Icon(
                    Icons.check_circle_outline,
                  ),
                  label: const Text(
                    'Bevásárlás befejezése',
                  ),
                ),
              ),
            ),
          ],
        );
      },
    )),
    );
  }
}
