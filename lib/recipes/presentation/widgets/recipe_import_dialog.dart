import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../domain/models/recipe_import_draft.dart';
import '../../domain/services/recipe_text_parser.dart';

Future<RecipeImportDraft?> showRecipeImportDialog(BuildContext context) =>
    showDialog<RecipeImportDraft>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const RecipeImportDialog(),
    );

class RecipeImportDialog extends StatefulWidget {
  const RecipeImportDialog({super.key, this.parse});

  /// Optional pure parser dependency for error-path tests.
  final RecipeImportDraft Function(String)? parse;
  static const maxCharacters = 20000;

  @override
  State<RecipeImportDialog> createState() => _RecipeImportDialogState();
}

class _RecipeImportDialogState extends State<RecipeImportDialog> {
  final _text = TextEditingController();
  String? _error;
  bool _confirming = false;
  bool _finished = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _process() {
    if (_finished || _confirming || _text.text.trim().isEmpty) return;
    // Same Unicode code-point convention as shopping import; never truncate.
    if (_text.text.runes.length > RecipeImportDialog.maxCharacters) {
      setState(
        () => _error =
            'A beillesztett recept túl hosszú. Legfeljebb 20 000 karakter dolgozható fel.',
      );
      return;
    }
    try {
      final draft = (widget.parse ?? const RecipeTextParser().parse)(
        _text.text,
      );
      _finished = true;
      Navigator.of(context).pop(draft);
    } catch (error) {
      debugPrint('Recipe import processing failed: ${error.runtimeType}');
      setState(
        () => _error = 'Nem sikerült feldolgozni a receptet. Próbáld újra.',
      );
    }
  }

  Future<void> _close() async {
    if (_confirming || _finished) return;
    if (_text.text.trim().isEmpty) {
      _finished = true;
      Navigator.of(context).pop();
      return;
    }
    _confirming = true;
    FocusScope.of(context).unfocus();
    final leave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (confirmationContext) => AlertDialog(
        title: const Text('Megszakítod az importálást?'),
        content: const SingleChildScrollView(
          child: Text('A beillesztett recept elveszik.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(confirmationContext).pop(false),
            child: const Text('Mégsem'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(confirmationContext).pop(true),
            child: const Text('Kilépés'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    _confirming = false;
    if (leave == true) {
      _finished = true;
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _close();
    },
    child: Dialog(
      insetPadding: const EdgeInsets.all(16),
      constraints: const BoxConstraints(minWidth: 0, maxWidth: 640),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) => SizedBox(
          width: constraints.maxWidth,
          height: math.min(600, constraints.maxHeight * 0.9),
          // Dialog already subtracts keyboard insets and safe areas.
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Recept importálása',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      onPressed: _close,
                      tooltip: 'Bezárás',
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Illeszd be a teljes receptet. Feldolgozás után a receptszerkesztőben ellenőrizheted és módosíthatod.',
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('recipe-import-text'),
                  controller: _text,
                  minLines: 5,
                  maxLines: 10,
                  keyboardType: TextInputType.multiline,
                  decoration: InputDecoration(
                    labelText: 'Recept szövege',
                    border: const OutlineInputBorder(),
                    errorText: _error,
                    errorMaxLines: 4,
                  ),
                  onChanged: (_) => setState(() => _error = null),
                ),
                const SizedBox(height: 16),
                OverflowBar(
                  spacing: 8,
                  overflowSpacing: 8,
                  children: [
                    TextButton(onPressed: _close, child: const Text('Mégse')),
                    FilledButton(
                      onPressed: _text.text.trim().isEmpty ? null : _process,
                      child: const Text('Feldolgozás'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
