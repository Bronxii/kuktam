import 'package:cloud_functions/cloud_functions.dart';
import 'callable_gateways.dart';

/// Opt-in per artifact; ordinary builds never enable purchases or restore.
const bool onlineMonetizationEnabled = bool.fromEnvironment(
  'KUKTAM_ONLINE_MONETIZATION',
  defaultValue: false,
);

const productionFunctionsRegion = 'europe-west1';

/// Called lazily by the coordinator only for an enabled, current session.
FirebaseCallableTransport productionMonetizationTransport(
  String uid,
  bool Function() isCurrent,
) => FirebaseCallableTransport(
  functions: FirebaseFunctions.instanceFor(region: productionFunctionsRegion),
  isCurrent: isCurrent,
);
