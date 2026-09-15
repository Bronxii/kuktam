import 'package:shared_preferences/shared_preferences.dart';

/// App/device preference. It deliberately has no account or UID parameter.
abstract interface class WalkthroughStore {
  Future<bool> isCompleted();
  Future<void> complete();
}

class SharedPreferencesWalkthroughStore implements WalkthroughStore {
  const SharedPreferencesWalkthroughStore({this.preferences});

  static const completedKey = 'walkthroughCompleted';
  final SharedPreferencesAsync? preferences;

  // Instantiate lazily so platform/read errors are handled by the gate.
  SharedPreferencesAsync get _client =>
      preferences ?? SharedPreferencesAsync();

  @override
  Future<bool> isCompleted() async =>
      await _client.getBool(completedKey) ?? false;

  @override
  Future<void> complete() async {
    await _client.setBool(completedKey, true);
  }
}
