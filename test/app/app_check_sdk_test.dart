// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/app/app_check_monitor.dart';
import 'package:kuktam/app/firebase_startup.dart';
import 'package:kuktam/firebase_options.dart';
import '../monetization/production_composition_test.dart'
    show ProductionCoreMock;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'production bootstrap calls real App Check SDK before app composition',
    () async {
      TestFirebaseCoreHostApi.setUp(ProductionCoreMock());
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final events = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      for (final method in ['activate', 'getToken', 'registerTokenListener']) {
        final channel = BasicMessageChannel<Object?>(
          'dev.flutter.pigeon.firebase_app_check_platform_interface.FirebaseAppCheckHostApi.$method',
          const StandardMessageCodec(),
        );
        messenger.setMockDecodedMessageHandler<Object?>(channel, (
          message,
        ) async {
          final args = message as List;
          expect(args.first, '[DEFAULT]');
          if (method == 'activate') {
            events.add('activate');
            expect(args[1], kDebugMode ? 'debug' : 'playIntegrity');
            expect(args[3], isNull); // No embedded debug credential.
            return [null];
          }
          if (method == 'getToken') {
            events.add('token');
            expect(args[1], false); // Do not force repeated attestation.
            return ['synthetic-token-never-log'];
          }
          return ['test-appcheck-events'];
        });
        addTearDown(
          () => messenger.setMockDecodedMessageHandler<Object?>(channel, null),
        );
      }
      const stream = MethodChannel('test-appcheck-events');
      messenger.setMockMethodCallHandler(stream, (_) async => null);
      addTearDown(() => messenger.setMockMethodCallHandler(stream, null));
      final logs = <String>[];
      final priorPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        logs.add(message ?? '');
      };
      addTearDown(() => debugPrint = priorPrint);
      await startFirebaseApp(
        initializeFirebase: () async {
          await Firebase.initializeApp(options: DefaultFirebaseOptions.android);
          events.add('firebase');
        },
        composeApp: () async {
          events.add('compose');
        },
      );
      expect(events, ['firebase', 'activate', 'token', 'compose']);
      expect(logs.join(), isNot(contains('synthetic-token-never-log')));
    },
  );
  test(
    'unsupported platform does not accidentally activate Android/Apple providers',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await initializeAppCheckMonitor();
    },
  );
}
