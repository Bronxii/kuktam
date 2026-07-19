import 'package:flutter/material.dart';

class IngredientRowData {
  IngredientRowData({
    String name = '',
    String quantity = '',
    String unit = 'g',
  })  : nameController = TextEditingController(text: name),
        amountController = TextEditingController(text: quantity),
        selectedUnit = unit;

  final TextEditingController nameController;
  final TextEditingController amountController;

  String selectedUnit;

  void dispose() {
    nameController.dispose();
    amountController.dispose();
  }
}
class IngredientRow extends StatefulWidget {
  const IngredientRow({
    required this.data,
    required this.units,
    required this.onRemove,
    super.key,
  });

  final IngredientRowData data;
  final List<String> units;
  final VoidCallback onRemove;

  @override
  State<IngredientRow> createState() => _IngredientRowState();
}
class _IngredientRowState extends State<IngredientRow> {
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: TextField(
            controller: widget.data.nameController,
            decoration: const InputDecoration(
              labelText: 'Hozzávaló',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: TextField(
            controller: widget.data.amountController,
            decoration: const InputDecoration(
              labelText: 'Mennyiség',
              border: OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 76,
          child: DropdownButtonFormField<String>(
            initialValue: widget.data.selectedUnit,
            decoration: const InputDecoration(
              labelText: 'Egység',
              border: OutlineInputBorder(),
            ),
            items: widget.units
                .map(
                  (unit) => DropdownMenuItem<String>(
                value: unit,
                child: Text(unit),
              ),
            )
                .toList(),
            onChanged: (value) {
              if (value == null) {
                return;
              }

              setState(() {
                widget.data.selectedUnit = value;
              });
            },
          ),
        ),
        IconButton(
          onPressed: widget.onRemove,
          tooltip: 'Hozzávaló törlése',
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    );
  }
}