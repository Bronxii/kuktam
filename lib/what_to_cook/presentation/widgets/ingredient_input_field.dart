import 'package:flutter/material.dart';

class IngredientInputField extends StatefulWidget {
  const IngredientInputField({
    required this.onIngredientAdded,
    super.key,
  });

  final ValueChanged<String> onIngredientAdded;

  @override
  State<IngredientInputField> createState() => _IngredientInputFieldState();
}

class _IngredientInputFieldState extends State<IngredientInputField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  bool get _canAdd => _controller.text.trim().isNotEmpty;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submitIngredient() {
    final ingredient = _controller.text.trim();

    if (ingredient.isEmpty) {
      return;
    }

    widget.onIngredientAdded(ingredient);

    _controller.clear();

    setState(() {});

    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      textInputAction: TextInputAction.done,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        labelText: 'Alapanyag',
        hintText: 'Például: csirkemell',
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          tooltip: 'Alapanyag hozzáadása',
          onPressed: _canAdd ? _submitIngredient : null,
          icon: const Icon(Icons.add),
        ),
      ),
      onChanged: (_) {
        setState(() {});
      },
      onSubmitted: (_) {
        _submitIngredient();
      },
    );
  }
}