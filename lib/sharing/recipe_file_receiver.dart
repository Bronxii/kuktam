import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../core/account_deletion_signal.dart';
import '../recipes/domain/models/recipe.dart';
import 'recipe_share_codec.dart';

class RecipeFileReceiver extends ChangeNotifier {
  RecipeFileReceiver({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('kuktam/recipe_file') {
    AccountDeletionSignal.generation.addListener(_deleting);
  }
  static final instance = RecipeFileReceiver();
  final MethodChannel _channel;
  final _pending = Queue<Recipe>();
  final _startedEvents = <String, int>{};
  final _seen = <String>{};
  StreamSubscription<String?>? _auth;
  String? _uid;
  String? Function()? _currentUid;
  int generation = 0;
  String? _notice;
  bool _started = false, _draining = false, _again = false;
  bool get hasPending => _pending.isNotEmpty || _notice != null;
  Recipe? take() => _pending.isEmpty ? null : _pending.removeFirst();
  String? takeNotice() {
    final n = _notice;
    _notice = null;
    return n;
  }

  void bindSession(
    Stream<String?> users,
    String? initialUid, {
    String? Function()? currentUid,
  }) {
    _currentUid = currentUid;
    updateSession(initialUid);
    _auth = users.listen(
      updateSession,
      onError: (Object _) => updateSession(null),
    );
  }

  void updateSession(String? uid) {
    if (_uid == uid) return;
    // Login may adopt unauthenticated pending input. A previous account may not transfer it.
    if (_uid != null) {
      generation++;
      _pending.clear();
      _startedEvents.clear();
      _notice = null;
    }
    _uid = uid;
    notifyListeners();
  }

  void _deleting() {
    generation++;
    _pending.clear();
    _startedEvents.clear();
    notifyListeners();
  }

  void check(int expected) {
    if (generation != expected ||
        _uid == null ||
        (_currentUid != null && _currentUid!() != _uid) ||
        AccountDeletionSignal.active) {
      throw const RecipeShareFailure('session');
    }
  }

  void accept(Object? event) {
    if (event is! Map || event['id'] is! String) return;
    final id = event['id'] as String;
    if (id.isEmpty) return;
    if (event['stage'] == 'begin') {
      if (_seen.contains(id)) return;
      _seen.add(id);
      if (_seen.length > 512) _seen.remove(_seen.first);
      if (_startedEvents.length + _pending.length >= 10) {
        _notice = const RecipeShareFailure('busy').message;
      } else {
        _startedEvents[id] = generation;
      }
    } else {
      final expected = _startedEvents.remove(id);
      if (expected == null || expected != generation) return;
      try {
        if (event['error'] != null) {
          final error = event['error'];
          throw RecipeShareFailure(error == 'size' ? 'size' : 'read');
        }
        final bytes = event['bytes'];
        if (bytes is! List<int>) throw const RecipeShareFailure('invalid');
        _pending.add(RecipeShareCodec.decode(bytes));
      } on RecipeShareFailure catch (e) {
        _notice = e.message;
      }
    }
    notifyListeners();
  }

  bool _picking = false;
  Future<bool> pickFile() async {
    if (_picking) return false;
    _picking = true;
    final expected = generation;
    try {
      check(expected);
      final bytes = await _channel.invokeMethod<Uint8List>('pick');
      check(expected);
      if (bytes == null) return false;
      if (_pending.length + _startedEvents.length >= 10) {
        throw const RecipeShareFailure('busy');
      }
      _pending.add(RecipeShareCodec.decode(bytes));
      notifyListeners();
      return true;
    } on PlatformException catch (e) {
      throw RecipeShareFailure(
        const ['size', 'format', 'busy'].contains(e.code) ? e.code : 'read',
      );
    } finally {
      _picking = false;
    }
  }

  Future<void> start() async {
    if (_started || kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    _started = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'pending') await _drain();
    });
    await _drain();
  }

  Future<void> _drain() async {
    if (_draining) {
      _again = true;
      return;
    }
    _draining = true;
    try {
      do {
        _again = false;
        Object? event;
        while ((event = await _channel.invokeMethod<Object?>('take')) != null) {
          accept(event);
        }
      } while (_again);
    } on MissingPluginException {
      /* Non-Android tests. */
    } on PlatformException {
      _notice = const RecipeShareFailure('read').message;
      notifyListeners();
    } finally {
      _draining = false;
    }
  }

  @override
  void dispose() {
    AccountDeletionSignal.generation.removeListener(_deleting);
    _auth?.cancel();
    super.dispose();
  }
}
