import { VoidedPurchaseApi, VoidedLookupError } from '../src/billing/voided-purchase-api';
import { PlayPurchaseQuery } from '../src/billing/play-purchase-api';
export class FakeVoidedApi implements VoidedPurchaseApi {
  calls = 0;
  handler: (query: PlayPurchaseQuery) => Promise<unknown | null> = async () => null;
  respond(value: unknown | null) { this.handler = async () => value; }
  fail(code: 'unavailable' | 'configuration') { this.handler = async () => { throw new VoidedLookupError(code); }; }
  async lookup(query: PlayPurchaseQuery) { this.calls++; return this.handler(query); }
}
