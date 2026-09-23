import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../data/repositories/shopping_repository.dart';

import '../../domain/models/shopping_import_draft.dart';
import '../../domain/services/shopping_text_parser.dart';
import '../../domain/shopping_units.dart';

Future<void> showShoppingImportDialog(BuildContext context) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => const ShoppingImportDialog(),
);

class ShoppingImportDialog extends StatefulWidget {
  const ShoppingImportDialog({super.key, this.addItems});
  final Future<void> Function(List<ShoppingItemInput>)? addItems;

  @override
  State<ShoppingImportDialog> createState() => _ShoppingImportDialogState();
}

class _ShoppingImportDialogState extends State<ShoppingImportDialog> {
  final _text = TextEditingController();
  final _rows = <_ImportRow>[];
  bool _preview = false;
  bool _confirming = false;
  bool _saving = false;
  String? _error;

  bool get _canSave =>
      !_saving &&
      _rows.isNotEmpty &&
      _rows.every((row) => row.validationError == null);

  void _addRow() {
    if (_saving || _rows.length >= ShoppingTextParser.maxItems) return;
    setState(() => _rows.add(_ImportRow.manual()));
  }

  void _removeRow(_ImportRow row) {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    setState(() => _rows.remove(row));
    // Dispose after the removed TextFields have detached from their controllers.
    WidgetsBinding.instance.addPostFrameCallback((_) => row.dispose());
  }

  Future<void> _save() async {
    if (!_canSave || _confirming) return;
    final snapshot = List<ShoppingItemInput>.unmodifiable([
      for (final row in _rows)
        (
          name: row.name.text.trim(),
          quantity: row.parsedQuantity!,
          unit: row.unit,
        ),
    ]);
    setState(() {
      _saving = true;
      _error = null;
    });
    FocusScope.of(context).unfocus();
    try {
      final add = widget.addItems ?? ShoppingRepository().addOrMergeItems;
      await add(snapshot);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${snapshot.length} tétel hozzáadva a bevásárlólistához.',
          ),
        ),
      );
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Nem sikerült hozzáadni a tételeket. Próbáld újra.';
      });
    }
  }

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
    if (_confirming || _saving) return;
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
                      onPressed: _saving ? null : _close,
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
                  TextButton(
                    onPressed:
                        _saving || _rows.length >= ShoppingTextParser.maxItems
                        ? null
                        : _addRow,
                    child: const Text('Tétel hozzáadása'),
                  ),
                  if (_error != null)
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  FilledButton(
                    onPressed: _canSave ? _save : null,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
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
              enabled: !_saving,
              onChanged: (_) => setState(() {}),
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
              enabled: !_saving,
              onChanged: (_) => setState(() {}),
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
            flex: 3,
            child: DropdownButtonFormField<String>(
              initialValue: row.unit,
              isExpanded: true,
              // 8px top padding + five 48px rows + half of the next row.
              menuMaxHeight: 8 + 5.5 * kMinInteractiveDimension,
              iconSize: 18,
              decoration: const InputDecoration(
                labelText: 'Egység',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 4,
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
              onChanged: _saving
                  ? null
                  : (unit) {
                      if (unit != null) setState(() => row.unit = unit);
                    },
            ),
          ),
          IconButton(
            tooltip: 'Tétel törlése',
            onPressed: _saving ? null : () => _removeRow(row),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 48),
            iconSize: 18,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      if (row.validationError != null)
        Text(
          row.validationError!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      if (row.draft?.hasError ?? false)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'A felismerés javítást igényel. Eredeti szöveg: ${row.draft!.rawSegment}',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
    ],
  );
}

class _ImportRow {
  _ImportRow(ShoppingImportDraft original)
    : draft = original,
      name = TextEditingController(text: original.name),
      quantity = TextEditingController(text: original.quantityText),
      unit = original.unit;
  _ImportRow.manual()
    : draft = null,
      name = TextEditingController(),
      quantity = TextEditingController(text: '1'),
      unit = 'db';
  final Key key = UniqueKey();
  final ShoppingImportDraft? draft;
  final TextEditingController name;
  final TextEditingController quantity;
  String unit;

  // Same decimal conversion as the manual item dialog, with finite safeguards.
  double? get parsedQuantity =>
      double.tryParse(quantity.text.trim().replaceAll(',', '.'));
  String? get validationError {
    if (name.text.trim().isEmpty) return 'A tétel neve nem lehet üres.';
    final value = parsedQuantity;
    if (value == null || !value.isFinite || value <= 0) {
      return 'Adj meg érvényes, pozitív mennyiséget.';
    }
    if (!shoppingUnits.contains(unit)) {
      return 'Válassz érvényes mértékegységet.';
    }
    if ((unit == 'kg' || unit == 'l') && !(value * 1000).isFinite) {
      return 'Túl nagy mennyiség.';
    }
    return null;
  }

  void dispose() {
    name.dispose();
    quantity.dispose();
  }
}
