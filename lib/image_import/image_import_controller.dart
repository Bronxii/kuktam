import 'dart:async';
import 'package:flutter/foundation.dart';
import 'image_import_model.dart';

enum ImageImportState {
  idle,
  imagesSelected,
  preparingImages,
  readyToImport,
  processingPlaceholder,
  error,
}

class ImageImportController extends ChangeNotifier {
  ImageImportController({
    required this.picker,
    required this.preparation,
    required this.validateSession,
    required this.sessionChanges,
    this.credits = const LocalImageCreditPreview(),
    this.policy = const ImageImportPolicy(),
    String Function()? operationId,
  }) : _operationId = operationId ?? newImageOperationId {
    sessionChanges.addListener(_sessionChanged);
    _sessionChanged();
  }
  final ImageImportPickerPort picker;
  final ImagePreparationPort preparation;
  final ImageCreditPreviewPort credits;
  final ImageImportPolicy policy;
  final void Function() validateSession;
  final Listenable sessionChanges;
  final String Function() _operationId;
  final _selected = <SelectedImportImage>[];
  final _prepared = <String, PreparedImportImage>{};
  final failures = <String, ImageImportFailure>{};
  ImageImportState state = ImageImportState.idle;
  ImageImportFailure? error;
  PreparedImageOperation? operation;
  bool busy = false, _disposed = false, invalidated = false;
  int _epoch = 0;
  List<SelectedImportImage> get images => List.unmodifiable(_selected);
  List<PreparedImportImage> get prepared => List.unmodifiable(
    _selected
        .where((i) => _prepared.containsKey(i.id))
        .map((i) => _prepared[i.id]!),
  );
  int get creditCost => _selected.length;
  bool get editable => !busy && !invalidated && operation == null;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _valid(int epoch) {
    if (_disposed || invalidated || epoch != _epoch) return false;
    try {
      validateSession();
      return true;
    } catch (_) {
      invalidate();
      return false;
    }
  }

  void _sessionChanged() {
    if (!_disposed && !invalidated) {
      try {
        validateSession();
      } catch (_) {
        invalidate();
      }
    }
  }

  void invalidate() {
    if (invalidated) return;
    invalidated = true;
    _epoch++;
    operation = null;
    error = const ImageImportFailure('session');
    state = ImageImportState.error;
    _clear();
    _notify();
  }

  void _clear() {
    final old = List<SelectedImportImage>.of(_selected);
    final output = _prepared.values.toList();
    _selected.clear();
    _prepared.clear();
    failures.clear();
    unawaited(_release(old, output));
  }

  Future<void> _release(
    List<SelectedImportImage> input,
    List<PreparedImportImage> output,
  ) async {
    try {
      await picker.release(input);
    } catch (_) {
      /* own-cache startup sweep */
    }
    try {
      await preparation.release(output);
    } catch (_) {
      /* own-cache startup sweep */
    }
  }

  Future<void> add() async {
    if (!editable) return;
    final epoch = _epoch;
    if (!_valid(epoch)) return;
    if (_selected.length == ImageImportPolicy.maxImages) {
      error = const ImageImportFailure('limit');
      _notify();
      return;
    }
    busy = true;
    error = null;
    _notify();
    try {
      final incoming = await picker.pick(
        ImageImportPolicy.maxImages - _selected.length,
        policy,
      );
      if (!_valid(epoch)) {
        await _release(incoming, []);
        return;
      }
      if (incoming.length + _selected.length > ImageImportPolicy.maxImages ||
          incoming.map((e) => e.id).toSet().length != incoming.length ||
          incoming.any((e) => _selected.any((old) => old.id == e.id))) {
        await _release(incoming, []);
        throw const ImageImportFailure('limit');
      }
      // Repeated content is deliberately allowed: no hidden dedupe or price change.
      _selected.addAll(incoming);
      for (final i in incoming) {
        if (i.failure != null) failures[i.id] = i.failure!;
      }
      _refresh();
    } catch (e) {
      if (_valid(epoch)) {
        error = e is ImageImportFailure ? e : const ImageImportFailure('read');
      }
    } finally {
      busy = false;
      _notify();
    }
  }

  void remove(int index) {
    if (!editable || !_valid(_epoch)) return;
    final item = _selected.removeAt(index);
    final output = _prepared.remove(item.id);
    failures.remove(item.id);
    unawaited(_release([item], [?output]));
    error = null;
    _refresh();
    _notify();
  }

  void move(int from, int to) {
    if (!editable || !_valid(_epoch) || from == to) return;
    final item = _selected.removeAt(from);
    _selected.insert(to, item);
    _notify();
  }

  void _refresh() {
    state = _selected.isEmpty
        ? ImageImportState.idle
        : failures.isNotEmpty
        ? ImageImportState.error
        : _prepared.length == _selected.length
        ? ImageImportState.readyToImport
        : ImageImportState.imagesSelected;
  }

  Future<void> prepare() async {
    if (!editable || !_valid(_epoch)) return;
    if (_selected.isEmpty) {
      error = const ImageImportFailure('empty');
      _notify();
      return;
    }
    final epoch = _epoch;
    busy = true;
    error = null;
    state = ImageImportState.preparingImages;
    _notify();
    try {
      for (final item in List<SelectedImportImage>.of(_selected)) {
        if (!_valid(epoch)) return;
        if (_prepared.containsKey(item.id)) continue;
        try {
          if (item.failure != null) throw item.failure!;
          final output = await preparation.prepare(item, policy);
          if (!_valid(epoch)) {
            await _release([], [output]);
            return;
          }
          _prepared[item.id] = output;
          failures.remove(item.id);
        } catch (e) {
          if (!_valid(epoch)) return;
          failures[item.id] = e is ImageImportFailure
              ? e
              : const ImageImportFailure('prepare');
        }
        _notify();
      }
      if (_valid(epoch)) _refresh();
    } finally {
      busy = false;
      _notify();
    }
  }

  void start() {
    if (!editable || !_valid(_epoch)) return;
    if (state != ImageImportState.readyToImport || failures.isNotEmpty) return;
    if (credits.balance < creditCost) {
      error = const ImageImportFailure('credits');
      _notify();
      return;
    }
    operation = PreparedImageOperation(_operationId(), prepared);
    state = ImageImportState.processingPlaceholder;
    _notify(); // Local only: no reservation, deduction, network or extraction.
  }

  @override
  void dispose() {
    sessionChanges.removeListener(_sessionChanged);
    _disposed = true;
    _epoch++;
    _clear();
    super.dispose();
  }
}
