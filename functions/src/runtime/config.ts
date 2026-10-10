import { productionAdapterConfig } from '../adapters/config';
export const runtimeConfig = Object.freeze({
  packageName: productionAdapterConfig.packageName,
  productId: productionAdapterConfig.productId,
  region: 'europe-west1',
  topic: 'kuktam-play-rtdn',
  hmacCurrentVersion: 'v1',
  identityParameter: 'KUKTAM_RUNTIME_SERVICE_ACCOUNT',
  hmacSecretName: 'KUKTAM_BINDING_KEYS',
  recentAuthMaxAgeMs: 300000,
  schedule: 'every 5 minutes',
  timeoutSeconds: 300,
  dispatcherLeaseMs: 360000,
});
