import 'app_check_monitor.dart';

/// Only App Check is best-effort. Firebase initialization and composition
/// failures retain their original behavior and are never swallowed here.
Future<void> startFirebaseApp({
  required Future<void> Function() initializeFirebase,
  required Future<void> Function() composeApp,
  Future<void> Function() initializeAppCheck = initializeAppCheckMonitor,
}) async {
  await initializeFirebase();
  await initializeAppCheck();
  await composeApp();
}
