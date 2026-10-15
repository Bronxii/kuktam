import 'dart:async';
import 'image_import/local_image_preparation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app/app.dart';
import 'sharing/text_share_controller.dart';
import 'sharing/recipe_file_receiver.dart';
import 'firebase_options.dart';
import 'billing/android_billing_adapter.dart';
import 'entitlements/data/entitlement_contracts.dart';
import 'features/auth/data/repositories/auth_repository.dart';
import 'monetization/monetization_coordinator.dart';
import 'monetization/secure_entitlement_storage.dart';
import 'monetization/production_composition.dart';
import 'pro/monetization_host.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(LocalImagePreparation().cleanupStale().catchError((Object _) {}));

  await TextShareController.instance.start();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final auth = AuthRepository();
  RecipeFileReceiver.instance.bindSession(
    auth.authStateChanges().map((u) => u != null && !AuthRepository.requiresEmailVerification(u) ? u.uid : null),
    auth.currentUser != null && !AuthRepository.requiresEmailVerification(auth.currentUser) ? auth.currentUser!.uid : null,
    currentUid: () => auth.currentUser?.uid,
  );
  await RecipeFileReceiver.instance.start();
  final monetization = MonetizationCoordinator(
    billing: AndroidBillingAdapter(),
    storage: SecureEntitlementStorage(),
    clock: SystemEntitlementClock(),
    onlineEnabled: onlineMonetizationEnabled,
    transportFactory: productionMonetizationTransport,
  );
  runApp(
    MonetizationHost(
      coordinator: monetization,
      userIds: auth.authStateChanges().map(
        (user) =>
            user != null && !AuthRepository.requiresEmailVerification(user)
            ? user.uid
            : null,
      ),
      child: KuktamApp(authRepository: auth),
    ),
  );
}
