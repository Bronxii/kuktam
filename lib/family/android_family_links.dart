import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Native inbox is volatile and drained once. No URI/token diagnostics.
class AndroidFamilyLinks {
  AndroidFamilyLinks({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('kuktam/family_links');
  final MethodChannel _channel;
  bool _draining = false, _again = false, _disposed = false;
  void Function(String)? _receive;
  Future<void> start(void Function(String) receive) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    _receive = receive;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'pending') await _drain();
    });
    await _drain();
  }

  Future<void> _drain() async {
    if (_disposed) return;
    if (_draining) {
      _again = true;
      return;
    }
    _draining = true;
    try {
      do {
        _again = false;
        Object? value;
        while (!_disposed &&
            (value = await _channel.invokeMethod<Object?>('take')) != null) {
          if (value is String) _receive?.call(value);
        }
      } while (_again && !_disposed);
    } on MissingPluginException {
      // Manual code entry remains available on non-Android hosts.
    } on PlatformException {
      // No credential/error details logged. Manual code remains available.
    } finally {
      _draining = false;
    }
  }

  void dispose() {
    _disposed = true;
    _receive = null;
    _channel.setMethodCallHandler(null);
  }
}
