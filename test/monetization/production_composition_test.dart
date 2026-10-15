// Firebase's test helper is supplied by the already locked platform package.
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/firebase_options.dart';
import 'package:kuktam/monetization/production_composition.dart';
import 'package:kuktam/monetization/callable_gateways.dart';

class ProductionCoreMock extends MockFirebaseApp {
  @override
  Future<List<CoreInitializeResponse>> initializeCore() async => [];

  @override
  Future<CoreInitializeResponse> initializeApp(
    String name,
    CoreFirebaseOptions options,
  ) async =>
      CoreInitializeResponse(name: name, options: options, pluginConstants: {});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('compile-time monetization is opt-in', () {
    expect(
      onlineMonetizationEnabled,
      const bool.fromEnvironment('KUKTAM_ONLINE_MONETIZATION'),
    );
  });

  test(
    'production composition uses real regional Firebase transport and session fence',
    () async {
      TestFirebaseCoreHostApi.setUp(ProductionCoreMock());
      await Firebase.initializeApp(options: DefaultFirebaseOptions.android);
      var current = true;
      final transport = productionMonetizationTransport(
        'test-user',
        () => current,
      );
      expect(transport, isA<FirebaseCallableTransport>());
      expect(
        transport.functions,
        same(FirebaseFunctions.instanceFor(region: 'europe-west1')),
      );
      expect(transport.functions.app.options.projectId, 'kuktam-67768');
      expect(transport.isCurrent(), isTrue);
      final calls = <String>[];
      const functionsChannel = BasicMessageChannel<Object?>(
        'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call',
        StandardMessageCodec(),
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(functionsChannel, (
            call,
          ) async {
            final args = Map<String, dynamic>.from((call as List).first as Map);
            expect(args['region'], 'europe-west1');
            expect(args['appName'], '[DEFAULT]');
            expect(args['origin'], isNull);
            expect(args['port'], isNull);
            calls.add(args['functionName'] as String);
            return [<String, Object?>{}];
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockDecodedMessageHandler<Object?>(functionsChannel, null),
      );
      for (final name in [
        'prepareProPurchase',
        'verifyProPurchase',
        'getEntitlementProof',
      ]) {
        await transport.call(name, {});
      }
      expect(calls, [
        'prepareProPurchase',
        'verifyProPurchase',
        'getEntitlementProof',
      ]);
      current = false;
      for (final name in [
        'prepareProPurchase',
        'verifyProPurchase',
        'getEntitlementProof',
      ]) {
        await expectLater(
          transport.call(name, {}),
          throwsA(isA<TransportFailure>()),
        );
      }
    },
  );
}
