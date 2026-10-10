import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Session-only queue: no entitlement, network, persistence or parsing.
class TextShareController extends ChangeNotifier {
  TextShareController({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('kuktam/text_share');
  static final instance = TextShareController();
  final MethodChannel _channel;
  final Queue<String> _pending = Queue();
  final Set<String> _seen = {};
  bool _started = false;
  bool _draining = false;
  bool _again = false;
  String? _notice;

  bool get hasPending => _pending.isNotEmpty || _notice != null;
  String? take() => _pending.isEmpty ? null : _pending.removeFirst();
  String? takeNotice() {
    final notice = _notice;
    _notice = null;
    return notice;
  }

  /// Public transport seam for deterministic local tests.
  void accept(Object? event) {
    if (event is! Map || event['id'] is! String || event['text'] is! String) {
      return;
    }
    final id = event['id'] as String;
    final text = event['text'] as String;
    if (id.isEmpty || _seen.contains(id)) return;
    _seen.add(id);
    if (_seen.length > 512) _seen.remove(_seen.first);
    if (text.trim().isEmpty) return;
    if (text.runes.length > 20000) {
      _notice = 'Legfeljebb 20 000 karakter osztható meg.';
    } else if (_pending.length >= 10) {
      _notice =
          'Előbb fejezd be a várakozó importokat, majd oszd meg újra a szöveget.';
    } else {
      _pending.add(
        text,
      ); // Preserve accents, whitespace and line breaks exactly.
    }
    notifyListeners();
  }

  static bool isUrlOnly(String text) {
    final value = text.trim();
    if (RegExp(r'\s').hasMatch(value)) return false;
    final uri = Uri.tryParse(value);
    return (uri != null &&
            (uri.scheme == 'http' || uri.scheme == 'https') &&
            uri.host.isNotEmpty) ||
        value.startsWith('www.');
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
      // Non-Android host/test: manual import remains available.
    } on PlatformException {
      _notice = 'Nem sikerült átvenni a megosztást. Oszd meg újra a szöveget.';
      notifyListeners();
    } finally {
      _draining = false;
    }
  }
}

/// Only signals navigation changes; MainScreen decides when its route is current.
class TextShareNavigationObserver extends NavigatorObserver {
  final changes = ValueNotifier<int>(0);
  void _changed() {
    WidgetsBinding.instance.addPostFrameCallback((_) => changes.value++);
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _changed();
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _changed();
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _changed();
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _changed();
}

final textShareNavigation = TextShareNavigationObserver();
