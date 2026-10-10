import 'package:flutter/foundation.dart';

/// Local account operations invalidate sensitive, in-flight exports.
abstract final class AccountDeletionSignal {
  static final generation = ValueNotifier<int>(0);
  static int _active = 0;
  static bool get active => _active > 0;
  static void begin() {
    _active++;
    generation.value++;
  }

  static void end() {
    _active--;
  }
}
