import { onCall, CallableOptions } from 'firebase-functions/v2/https';
import { MonetizationHandlers, transportResult } from './monetization';

/** Factory only: no Admin initialization, secret default, project selection or
 * exported deployed endpoints. A future composition root supplies all services.
 * Firebase's runtime verifies auth; body.uid is never trusted. */
export function createMonetizationCallables(handlers: MonetizationHandlers, options: CallableOptions) {
  return {
    prepareProPurchase: onCall(options, request => transportResult(() =>
      handlers.prepareProPurchase({ auth: request.auth ? { uid: request.auth.uid } : null, data: request.data }))),
    verifyProPurchase: onCall(options, request => transportResult(() =>
      handlers.verifyProPurchase({ auth: request.auth ? { uid: request.auth.uid } : null, data: request.data }))),
    getEntitlementProof: onCall(options, request => transportResult(() =>
      handlers.getEntitlementProof({ auth: request.auth ? { uid: request.auth.uid } : null, data: request.data }))),
  };
}
