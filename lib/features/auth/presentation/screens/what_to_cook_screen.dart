import 'package:flutter/material.dart';

class WhatToCookScreen extends StatelessWidget {
  const WhatToCookScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Milyen alapanyagok vannak otthon?',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 20),
          const TextField(
            decoration: InputDecoration(
              labelText: 'Alapanyag',
              hintText: 'Például: csirkemell',
              prefixIcon: Icon(Icons.restaurant),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.add),
            label: const Text('Új alapanyag hozzáadása'),
          ),
          const SizedBox(height: 32),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.search),
              label: const Text('Mit főzzek?'),
            ),
          ),
        ],
      ),
    );
  }
}