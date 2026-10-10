import { PlayAcknowledgmentApi } from '../src/billing/play-acknowledgment-api';
import { PlayPurchaseQuery } from '../src/billing/play-purchase-api';
export class FakeAcknowledgmentApi implements PlayAcknowledgmentApi {
  calls = 0;
  handler: (query: PlayPurchaseQuery) => Promise<unknown> = async () => ({ status: 'success' });
  async acknowledge(query: PlayPurchaseQuery): Promise<unknown> { this.calls++; return this.handler(query); }
}
