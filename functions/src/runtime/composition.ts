import { getApps, initializeApp, getApp } from 'firebase-admin/app';
import { getFirestore, Firestore } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';
import { AccountBinding } from '../billing/account-binding';
import { LifecycleStore } from '../billing/lifecycle-store';
import { AccountLifecycleStore } from '../accounts/account-lifecycle-store';
import { PurchaseVerifier, tokenHash } from '../billing/verify-purchase';
import { PurchaseAcknowledger } from '../billing/acknowledge-purchase';
import { AccountDeletionService } from '../accounts/account-deletion';
import { DeletionGateway } from '../accounts/deletion-gateway';
import { MonetizationHandlers } from '../transport/monetization';
import { RtdnProcessor } from '../billing/rtdn/processor';
import { Maintenance } from '../jobs/maintenance';
import { GooglePlayPurchaseAdapter, GooglePlayAcknowledgmentAdapter, GoogleVoidedFeed, GoogleVoidedPurchaseAdapter } from '../adapters/google-play';
import { createAdcPlayTransport, PlayTransport } from '../adapters/play-rest';
import { FirebaseAdminAuthDeletionAdapter } from '../adapters/firebase-auth';
import { AuthUserDeletionApi } from '../accounts/deletion-contract';
import { BindingKeyProvider } from '../billing/binding-key-provider';
import { MaintenanceDispatcher } from './maintenance-dispatcher';
import { loadBindingKeys } from './keys';
import { runtimeConfig } from './config';
/** One graph; dependencies injectable for local emulator tests. No initialization on import. */
export function compose(db: Firestore, rest: PlayTransport, auth: AuthUserDeletionApi, keys: BindingKeyProvider) {
  const binding = new AccountBinding(keys), store = new LifecycleStore(db);
  const play = new GooglePlayPurchaseAdapter(rest), ack = new GooglePlayAcknowledgmentAdapter(rest);
  const feed = new GoogleVoidedFeed(rest, Date.now);
  const voided = new GoogleVoidedPurchaseAdapter(play, feed, Date.now);
  const verifier = new PurchaseVerifier(db, play, binding, undefined, store);
  const acknowledger = new PurchaseAcknowledger(db, ack, undefined, undefined, undefined, store);
  const coordinatedVerifier: Pick<PurchaseVerifier, 'verify'> = {
    async verify(context, request) {
      const result = await verifier.verify(context, request);
      if (result.status === 'granted') {
        // The durable grant survives ack errors; maintenance owns retry recovery.
        try { await acknowledger.run(tokenHash((request as {purchaseToken:string}).purchaseToken)); } catch {}
      }
      return result;
    },
  };
  const deletion = new AccountDeletionService(db, auth, undefined, store);
  const maintenance = new Maintenance(db, {play, voided, ack, feed, binding, deletion});
  return {
    monetization: new MonetizationHandlers(db, new AccountLifecycleStore(db, binding), coordinatedVerifier),
    deletion: new DeletionGateway(deletion, Date.now, runtimeConfig.recentAuthMaxAgeMs),
    fallback: deletion,
    rtdn: new RtdnProcessor(db, runtimeConfig.topic, play, voided, binding),
    dispatcher: new MaintenanceDispatcher(db, maintenance),
  };
}
export type RuntimeServices = ReturnType<typeof compose>;
export function lazyProductionServices(secret: () => string): () => RuntimeServices {
  let services: RuntimeServices | undefined;
  return () => {
    if (services) return services;
    const keys = loadBindingKeys(secret()); // Missing secret fails closed, no fallback.
    const app = getApps().some(a => a.name === '[DEFAULT]') ? getApp() : initializeApp();
    services = compose(getFirestore(app), createAdcPlayTransport(),
      new FirebaseAdminAuthDeletionAdapter(getAuth(app)), keys);
    return services;
  };
}
