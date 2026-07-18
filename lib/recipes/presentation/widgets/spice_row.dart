import 'package:flutter/material.dart';

class SpiceRowData {
  SpiceRowData() : nameController = TextEditingController();

  final TextEditingController nameController;

  void dispose() {
    nameController.dispose();
  }
}
class SpiceRow extends StatelessWidget {
  const SpiceRow({
    required this.data,
    required this.onRemove,
    super.key,
  });

  final SpiceRowData data;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: data.nameController,
            decoration: const InputDecoration(
              labelText: 'Fűszer',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
        ),
        IconButton(
          onPressed: onRemove,
          tooltip: 'Fűszer törlése',
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    );
  }
}