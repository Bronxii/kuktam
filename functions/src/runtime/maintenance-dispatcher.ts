import { Firestore, Timestamp } from 'firebase-admin/firestore';
import { randomUUID } from 'node:crypto';
import { Maintenance, MaintenanceRun } from '../jobs/maintenance';
import { categories, Category } from '../jobs/maintenance-policy';
import { runtimeConfig } from './config';
/** Technical checkpoint only. Purchase state is exclusively owned by existing services. */
export class MaintenanceDispatcher {
  constructor(private readonly db: Firestore, private readonly maintenance: Pick<Maintenance, 'run'>,
    private readonly clock: () => Timestamp = Timestamp.now) {}
  async run(): Promise<void> {
    const ref = this.db.doc('billingRuntime/maintenance');
    const leaseId = randomUUID();
    const input = await this.db.runTransaction(async tx => {
      const doc = await tx.get(ref), value = doc.data();
      const now = this.clock();
      if (value) {
        if (Object.keys(value).sort().join(',') !== 'cursors,leaseId,leaseUntil,nextCategory,schemaVersion' || value.schemaVersion !== 1 || !categories.includes(value.nextCategory) ||
          !value.cursors || typeof value.cursors !== 'object' || Array.isArray(value.cursors) ||
          !(value.leaseUntil instanceof Timestamp) ||
          !(value.leaseId === null || typeof value.leaseId === 'string') ||
          Object.entries(value.cursors).some(([k,v]) => !categories.includes(k as Category) ||
            !(v === null || typeof v === 'string' && v.length < 1500))) throw new Error('invalidDispatcherState');
        if (value.leaseId && value.leaseUntil.toMillis() > now.toMillis()) return null;
      }
      const state = {nextCategory: value?.nextCategory ?? categories[0], cursors: value?.cursors ?? {}};
      tx.set(ref, {schemaVersion: 1, ...state, leaseId,
        leaseUntil: Timestamp.fromMillis(now.toMillis() + runtimeConfig.dispatcherLeaseMs)});
      return {now, ...state} as MaintenanceRun;
    });
    if (!input) return;
    // Failure leaves the durable lease for bounded crash takeover. Never reset cursors.
    const report = await this.maintenance.run(input);
    await this.db.runTransaction(async tx => {
      const doc = await tx.get(ref), current = doc.data();
      if (current?.leaseId !== leaseId || current.leaseUntil.toMillis() <= this.clock().toMillis()) return;
      tx.set(ref, {schemaVersion: 1, nextCategory: report.nextCategory, cursors: report.cursors,
        leaseId: null, leaseUntil: this.clock()});
    });
  }
}
