import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/models/shopping_import_draft.dart';
import '../../domain/services/shopping_text_parser.dart';
import '../../domain/shopping_units.dart';

Future<void> showShoppingImportDialog(BuildContext context) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => const ShoppingImportDialog(),
);

class ShoppingImportDialog extends StatefulWidget {
  const ShoppingImportDialog({super.key});

  @override
  State<ShoppingImportDialog> createState() => _ShoppingImportDialogState();
}

class _ShoppingImportDialogState extends State<ShoppingImportDialog> {
  final _text = TextEditingController();
  final _rows = <_ImportRow>[];
  bool _preview = false;
  bool _confirming = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _process() {
    if (_text.text.trim().isEmpty || _preview) return;
    try {
      final drafts = const ShoppingTextParser().parse(_text.text);
      if (drafts.isEmpty) {
        setState(() => _error = 'Nem találtam importálható tételt.');
        return;
      }
      FocusScope.of(context).unfocus();
      setState(() {
        _rows.addAll(drafts.map(_ImportRow.new));
        _preview = true;
        _error = null;
      });
    } on ShoppingTextLimitException catch (error) {
      setState(() {
        _error = error.limit == ShoppingTextLimit.characters
            ? 'Legfeljebb 20 000 karakter dolgozható fel.'
            : 'Legfeljebb 200 tétel dolgozható fel.';
      });
    }
  }

  Future<void> _close() async {
    if (_confirming) return;
    if (!_preview && _text.text.trim().isEmpty) {
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
        content: SingleChildScrollView(
          child: Text(
            _preview
                ? 'Az importált lista módosításai elvesznek.'
                : 'A beillesztett lista elveszik.',
          ),
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
    if (leave == true) Navigator.of(context).pop();
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
          // Dialog already accounts for keyboard insets and safe areas.
          height: math.min(720, constraints.maxHeight * 0.9),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _preview
                            ? 'Import előnézet'
                            : 'Bevásárlólista importálása',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Bezárás',
                      onPressed: _close,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _preview
                      ? 'Ellenőrizd a tételeket hozzáadás előtt.'
                      : 'Illeszd be a bevásárlólistát. Feldolgozás után minden tételt ellenőrizhetsz és módosíthatsz.',
                ),
                const SizedBox(height: 16),
                if (!_preview) ...[
                  TextField(
                    key: const ValueKey('import-text'),
                    controller: _text,
                    minLines: 5,
                    maxLines: 10,
                    keyboardType: TextInputType.multiline,
                    decoration: InputDecoration(
                      labelText: 'Bevásárlólista szövege',
                      border: const OutlineInputBorder(),
                      errorText: _error,
                      errorMaxLines: 3,
                    ),
                    onChanged: (_) => setState(() => _error = null),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _text.text.trim().isEmpty ? null : _process,
                    child: const Text('Feldolgozás'),
                  ),
                ] else ...[
                  for (final row in _rows)
                    Padding(
                      key: row.key,
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildRow(row),
                    ),
                  const FilledButton(
                    onPressed: null,
                    child: Text(
                      'Hozzáadás a bevásárlólistához',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _buildRow(_ImportRow row) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: TextField(
              controller: row.name,
              maxLines: 1,
              decoration: const InputDecoration(
                labelText: 'Név',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 14,
                ),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextField(
              controller: row.quantity,
              maxLines: 1,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Mennyiség',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 14,
                ),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<String>(
              initialValue: row.unit,
              isExpanded: true,
              menuMaxHeight: 240,
              iconSize: 18,
              decoration: const InputDecoration(
                labelText: 'Egység',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 14,
                ),
                border: OutlineInputBorder(),
              ),
              items: [
                for (final unit in shoppingUnits)
                  DropdownMenuItem(
                    value: unit,
                    child: Text(
                      unit,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (unit) {
                if (unit != null) setState(() => row.unit = unit);
              },
            ),
          ),
        ],
      ),
      if (row.draft.hasError)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'A felismerés javítást igényel. Eredeti szöveg: ${row.draft.rawSegment}',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
    ],
  );
}

class _ImportRow {
  _ImportRow(this.draft)
    : name = TextEditingController(text: draft.name),
      quantity = TextEditingController(text: draft.quantityText),
      unit = draft.unit;
  final Key key = UniqueKey();
  final ShoppingImportDraft draft;
  final TextEditingController name;
  final TextEditingController quantity;
  String unit;

  void dispose() {
    name.dispose();
    quantity.dispose();
  }
}
