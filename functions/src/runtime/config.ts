import { productionAdapterConfig } from '../adapters/config';
export const runtimeConfig = Object.freeze({
  packageName: productionAdapterConfig.packageName,
  productId: productionAdapterConfig.productId,
  region: 'europe-west1',
  topic: 'kuktam-play-rtdn',
  hmacCurrentVersion: 'v1',
  coreIdentityParameter: 'KUKTAM_CORE_RUNTIME_SERVICE_ACCOUNT',
  playIdentityParameter: 'KUKTAM_PLAY_RUNTIME_SERVICE_ACCOUNT',
  deletionIdentityParameter: 'KUKTAM_DELETION_RUNTIME_SERVICE_ACCOUNT',
  hmacSecretName: 'KUKTAM_BINDING_KEYS',
  recentAuthMaxAgeMs: 300000,
  schedule: 'every 5 minutes',
  timeoutSeconds: 300,
  dispatcherLeaseMs: 360000,
});
