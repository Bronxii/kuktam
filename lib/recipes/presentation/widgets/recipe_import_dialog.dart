import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../domain/models/recipe_import_draft.dart';
import '../../domain/services/recipe_text_parser.dart';

import '../../data/services/web_recipe_fetcher.dart';
import '../../data/services/web_recipe_import_loader.dart';
import '../../domain/models/web_recipe_import_handoff.dart';
import '../../domain/models/web_import_quality.dart';
import '../../domain/models/web_import_issue.dart';
import '../../domain/services/recipe_import_input_classifier.dart';
import 'web_import_error_message.dart';

typedef WebImportAction =
    Future<WebRecipeImportHandoff> Function(
      String input, {
      required WebImportCancellation cancellation,
      required String importId,
    });

Future<RecipeImportDraft?> showRecipeImportDialog(
  BuildContext context, {
  WebImportCancellation? lifetime,
  WebImportAction? importWeb,
}) => showDialog<RecipeImportDraft>(
  context: context,
  barrierDismissible: false,
  builder: (_) => RecipeImportDialog(lifetime: lifetime, importWeb: importWeb),
);

class RecipeImportDialog extends StatefulWidget {
  const RecipeImportDialog({
    super.key,
    this.parse,
    this.importWeb,
    this.lifetime,
  });
  final WebImportAction? importWeb;
  final WebImportCancellation? lifetime;

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
  bool _loading = false;
  int _operation = 0;
  static int _nextSession = 0;
  late final String _session = 'web-import-${_nextSession++}';
  WebImportCancellation? _cancellation;
  WebRecipeImportHandoff? _ready;
  void Function()? _removeLifetime;
  Route<dynamic>? _confirmationRoute;

  @override
  void initState() {
    super.initState();
    _removeLifetime = widget.lifetime?.listen(_endSession);
  }

  void _invalidate() {
    _operation++;
    _cancellation?.cancel();
    _cancellation = null;
  }

  void _endSession() {
    _invalidate();
    _finished = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final navigator = Navigator.of(context);
      final confirmation = _confirmationRoute;
      if (confirmation?.isActive ?? false) navigator.removeRoute(confirmation!);
      final route = ModalRoute.of(context);
      if (route?.isActive ?? false) navigator.removeRoute(route!);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  bool _active(int operation) =>
      mounted &&
      !_finished &&
      !_confirming &&
      operation == _operation &&
      !(widget.lifetime?.isCancelled ?? false);

  void _handoff(RecipeImportDraft draft) {
    if (!mounted || _finished || (widget.lifetime?.isCancelled ?? false)) {
      return;
    }
    _finished = true;
    _invalidate();
    Navigator.of(context).pop(draft);
  }

  Future<void> _processWeb() async {
    final operation = ++_operation;
    final cancellation = WebImportCancellation();
    _cancellation = cancellation;
    setState(() {
      _loading = true;
      _error = null;
      _ready = null;
    });
    try {
      final action = widget.importWeb ?? WebRecipeImportLoader().load;
      final result = await action(
        _text.text,
        cancellation: cancellation,
        importId: '$_session:$operation',
      );
      if (!_active(operation) || cancellation.isCancelled) return;
      if (!result.result.quality.allowsHandoff) {
        throw const WebImportFailure(WebImportIssueCode.invalidRecipe);
      }
      if (result.result.quality.quality == WebImportQuality.review) {
        setState(() => _ready = result);
      } else {
        _handoff(result);
      }
    } catch (error) {
      if (_active(operation) && !cancellation.isCancelled) {
        setState(() => _error = webImportErrorMessage(error));
      }
    } finally {
      if (_active(operation)) {
        setState(() => _loading = false);
      }
      if (identical(_cancellation, cancellation)) {
        _cancellation = null;
      }
      cancellation.cancel();
    }
  }

  @override
  void dispose() {
    _removeLifetime?.call();
    _invalidate();
    _text.dispose();
    super.dispose();
  }

  void _process() {
    if (_finished ||
        _confirming ||
        _loading ||
        (widget.lifetime?.isCancelled ?? false) ||
        _text.text.trim().isEmpty) {
      return;
    }
    // Same Unicode code-point convention as shopping import; never truncate.
    if (_text.text.runes.length > RecipeImportDialog.maxCharacters) {
      setState(
        () => _error =
            'A beillesztett recept túl hosszú. Legfeljebb 20 000 karakter dolgozható fel.',
      );
      return;
    }
    if (_ready != null) {
      _handoff(_ready!);
      return;
    }
    if (const RecipeImportInputClassifier().classify(_text.text) ==
        RecipeImportInputKind.web) {
      _processWeb();
      return;
    }
    try {
      final draft = (widget.parse ?? const RecipeTextParser().parse)(
        _text.text,
      );
      _handoff(draft);
    } catch (error) {
      debugPrint('Recipe import processing failed: ${error.runtimeType}');
      setState(
        () => _error = 'Nem sikerült feldolgozni a receptet. Próbáld újra.',
      );
    }
  }

  Future<void> _close() async {
    if (_confirming || _finished) return;
    _invalidate();
    setState(() {
      _loading = false;
      _ready = null;
    });
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
      builder: (confirmationContext) {
        _confirmationRoute = ModalRoute.of(confirmationContext);
        return AlertDialog(
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
        );
      },
    );
    _confirmationRoute = null;
    if (!mounted || _finished) return;
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
                  'Illessz be receptszöveget vagy receptlinket. A szerkesztőben ellenőrizheted és módosíthatod.',
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('recipe-import-text'),
                  controller: _text,
                  enabled: !_loading,
                  minLines: 5,
                  // Let the dialog scroll the text and actions together. A
                  // capped field consumes vertical drags in its own viewport.
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  decoration: InputDecoration(
                    labelText: 'Recept vagy link',
                    border: const OutlineInputBorder(),
                    errorText: _error,
                    errorMaxLines: 8,
                  ),
                  onChanged: (_) {
                    _invalidate();
                    setState(() {
                      _error = null;
                      _ready = null;
                    });
                  },
                ),
                const SizedBox(height: 16),
                if (_loading)
                  Semantics(
                    liveRegion: true,
                    label: 'Recept beolvasása folyamatban',
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: LinearProgressIndicator(),
                    ),
                  ),
                if (_ready != null)
                  Semantics(
                    liveRegion: true,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _ready!.source.requiresQuantityReview
                            ? 'Az automatikus import eredményét mentés előtt ellenőrizd, különösen a mennyiségeket.'
                            : 'Az automatikus import ellenőrzést igényel. Mentés előtt nézd át és szükség esetén javítsd a receptet.',
                      ),
                    ),
                  ),
                OverflowBar(
                  spacing: 8,
                  overflowSpacing: 8,
                  children: [
                    TextButton(onPressed: _close, child: const Text('Mégse')),
                    FilledButton(
                      onPressed: _loading || _text.text.trim().isEmpty
                          ? null
                          : _process,
                      child: Text(
                        _ready != null
                            ? 'Tovább a szerkesztőbe'
                            : 'Feldolgozás',
                      ),
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
