import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

enum AppCheckBuildMode { debug, profile, release }

AndroidAppCheckProvider androidAppCheckProvider(AppCheckBuildMode mode) =>
    mode == AppCheckBuildMode.debug
    ? const AndroidDebugProvider()
    : const AndroidPlayIntegrityProvider();

/// Android-only today; other platforms need their own reviewed provider setup.
/// This is monitoring, never an authorization decision or debug fallback.
Future<void> initializeAppCheckMonitor() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  final provider = androidAppCheckProvider(
    kDebugMode
        ? AppCheckBuildMode.debug
        : kProfileMode
        ? AppCheckBuildMode.profile
        : AppCheckBuildMode.release,
  );
  await activateAppCheckMonitor(
    activate: () =>
        FirebaseAppCheck.instance.activate(providerAndroid: provider),
    requestToken: () => FirebaseAppCheck.instance.getToken(false),
    diagnostic: (message) => debugPrint(message),
  );
}

/// The SDK attaches/refreshes tokens for Firebase requests. The initial probe
/// only warms the cache; neither its result nor its failure gates app access.
/// No exception text, stack trace or token is passed to diagnostics.
@visibleForTesting
Future<void> activateAppCheckMonitor({
  required Future<void> Function() activate,
  required Future<String?> Function() requestToken,
  required void Function(String) diagnostic,
}) async {
  try {
    await activate().timeout(const Duration(seconds: 5));
  } catch (_) {
    diagnostic('App Check monitor: activation unavailable; startup continues.');
    return;
  }
  try {
    final token = await requestToken().timeout(const Duration(seconds: 3));
    if (token == null || token.isEmpty) {
      diagnostic('App Check monitor: token unavailable; startup continues.');
    }
  } catch (_) {
    diagnostic('App Check monitor: token unavailable; startup continues.');
  }
}
