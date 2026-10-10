import { onCall } from 'firebase-functions/v2/https';
import { onMessagePublished } from 'firebase-functions/v2/pubsub';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { defineSecret, defineString } from 'firebase-functions/params';
import * as v1 from 'firebase-functions/v1';
import { runtimeConfig as config } from './runtime/config';
import { lazyProductionServices } from './runtime/composition';
import { createRuntimeHandlers } from './runtime/handlers';
// Declarations are safe at discovery/import time. Secret.value and Admin/ADC are lazy.
const keys = defineSecret(config.hmacSecretName);
const identity = defineString(config.identityParameter, {description:'Dedicated runtime service-account email; no default identity fallback.'});
const handlers = createRuntimeHandlers(lazyProductionServices(() => keys.value()));
const options = {region:config.region, serviceAccount:identity, secrets:[keys], timeoutSeconds:config.timeoutSeconds,
  maxInstances:5, enforceAppCheck:false};
export const prepareProPurchase = onCall(options, handlers.prepareProPurchase);
export const verifyProPurchase = onCall(options, handlers.verifyProPurchase);
export const getEntitlementProof = onCall(options, handlers.getEntitlementProof);
export const beginAccountDeletion = onCall(options, handlers.beginAccountDeletion);
export const finalizeAccountDeletion = onCall(options, handlers.finalizeAccountDeletion);
export const playRtdn = onMessagePublished({...options, topic:config.topic, retry:true}, handlers.rtdn);
export const billingMaintenance = onSchedule({...options, schedule:config.schedule,
  timeZone:'Etc/UTC', maxInstances:1, concurrency:1, retryCount:0}, handlers.maintenance);
// Installed v2 onUserDeleted is beta. Keep only this fallback on stable v1.
export const authUserDeleted = v1.region(config.region).runWith({secrets:[config.hmacSecretName],
  serviceAccount:identity, timeoutSeconds:config.timeoutSeconds, maxInstances:5, failurePolicy:true}).auth.user().onDelete(handlers.authDeleted);
