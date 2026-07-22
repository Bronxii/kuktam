import 'package:flutter/material.dart';

import '../../data/repositories/shopping_repository.dart';
import '../../domain/models/shopping_item.dart';

Future<void> showShoppingItemDialog({
  required BuildContext context,
  required ShoppingRepository shoppingRepository,
  ShoppingItem? item,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return _ShoppingItemDialog(
        shoppingRepository: shoppingRepository,
        item: item,
      );
    },
  );
}

class _ShoppingItemDialog extends StatefulWidget {
  const _ShoppingItemDialog({
    required this.shoppingRepository,
    this.item,
  });

  final ShoppingRepository shoppingRepository;
  final ShoppingItem? item;

  @override
  State<_ShoppingItemDialog> createState() => _ShoppingItemDialogState();
}

class _ShoppingItemDialogState extends State<_ShoppingItemDialog> {
  static const List<String> _units = [
    'g',
    'kg',
    'ml',
    'l',
    'db',
    'ek',
    'kk',
  ];

  late final TextEditingController _nameController;
  late final TextEditingController _quantityController;
  late String _selectedUnit;

  bool _isSaving = false;
  String? _errorMessage;

  bool get _isEditing => widget.item != null;

  @override
  void initState() {
    super.initState();

    final item = widget.item;

    _nameController = TextEditingController(
      text: item?.name ?? '',
    );

    _quantityController = TextEditingController(
      text: item == null
          ? '1'
          : item.quantity == item.quantity.roundToDouble()
          ? item.quantity.toInt().toString()
          : item.quantity.toString(),
    );

    _selectedUnit =
    item != null && _units.contains(item.unit) ? item.unit : 'db';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();

    final quantity = double.tryParse(
      _quantityController.text.trim().replaceAll(',', '.'),
    );

    if (name.isEmpty) {
      setState(() {
        _errorMessage = 'A tétel neve nem lehet üres.';
      });
      return;
    }

    if (quantity == null || quantity <= 0) {
      setState(() {
        _errorMessage = 'Adj meg érvényes mennyiséget.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final item = widget.item;

      if (item != null) {
        await widget.shoppingRepository.updateItem(
          id: item.id,
          name: name,
          quantity: quantity,
          unit: _selectedUnit,
        );
      } else {
        await widget.shoppingRepository.addOrMergeItem(
          name: name,
          quantity: quantity,
          unit: _selectedUnit,
        );
      }

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isSaving = false;
        _errorMessage = 'Nem sikerült menteni a tételt.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _isEditing ? 'Tétel szerkesztése' : 'Új tétel',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              enabled: !_isSaving,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Név',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _quantityController,
              enabled: !_isSaving,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Mennyiség',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedUnit,
              decoration: const InputDecoration(
                labelText: 'Mértékegység',
                border: OutlineInputBorder(),
              ),
              items: _units.map((unit) {
                return DropdownMenuItem<String>(
                  value: unit,
                  child: Text(unit),
                );
              }).toList(),
              onChanged: _isSaving
                  ? null
                  : (value) {
                if (value == null) {
                  return;
                }

                setState(() {
                  _selectedUnit = value;
                });
              },
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving
              ? null
              : () {
            Navigator.pop(context);
          },
          child: const Text('Mégse'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
            ),
          )
              : Text(
            _isEditing ? 'Mentés' : 'Hozzáadás',
          ),
        ),
      ],
    );
  }
}