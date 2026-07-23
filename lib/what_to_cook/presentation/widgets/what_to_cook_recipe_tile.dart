import 'package:flutter/material.dart';

import '../../../../recipes/domain/models/recipe.dart';

class WhatToCookRecipeTile extends StatelessWidget {
  const WhatToCookRecipeTile({
    required this.recipe,
    required this.onTap,
    super.key,
  });

  final Recipe recipe;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 6,
      ),
      child: ListTile(
        onTap: onTap,
        leading: const Icon(Icons.menu_book_outlined),
        title: Text(
          recipe.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${recipe.ingredients.length} hozzávaló',
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}