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
const coreIdentity = defineString(config.coreIdentityParameter, {description:'Core runtime service-account email; required, no default.'});
const playIdentity = defineString(config.playIdentityParameter, {description:'Play/billing runtime service-account email; required, no default.'});
const deletionIdentity = defineString(config.deletionIdentityParameter, {description:'Account deletion runtime service-account email; required, no default.'});
const handlers = createRuntimeHandlers(lazyProductionServices(() => keys.value()));
const options = {region:config.region, secrets:[keys], timeoutSeconds:config.timeoutSeconds,
  maxInstances:5, enforceAppCheck:false};
export const prepareProPurchase = onCall({...options, serviceAccount:coreIdentity}, handlers.prepareProPurchase);
export const verifyProPurchase = onCall({...options, serviceAccount:playIdentity}, handlers.verifyProPurchase);
export const getEntitlementProof = onCall({...options, serviceAccount:coreIdentity}, handlers.getEntitlementProof);
export const beginAccountDeletion = onCall({...options, serviceAccount:coreIdentity}, handlers.beginAccountDeletion);
export const finalizeAccountDeletion = onCall({...options, serviceAccount:deletionIdentity}, handlers.finalizeAccountDeletion);
export const playRtdn = onMessagePublished({...options, serviceAccount:playIdentity, topic:config.topic, retry:true}, handlers.rtdn);
export const billingMaintenance = onSchedule({...options, serviceAccount:playIdentity, schedule:config.schedule,
  timeZone:'Etc/UTC', maxInstances:1, concurrency:1, retryCount:0}, handlers.maintenance);
// Installed v2 onUserDeleted is beta. Keep only this fallback on stable v1.
export const authUserDeleted = v1.region(config.region).runWith({secrets:[config.hmacSecretName],
  serviceAccount:coreIdentity, timeoutSeconds:config.timeoutSeconds, maxInstances:5, failurePolicy:true}).auth.user().onDelete(handlers.authDeleted);
