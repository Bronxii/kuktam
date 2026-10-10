import { PlayPurchaseApi, PlayPurchaseQuery } from '../src/billing/play-purchase-api';

/** In-memory test double only. No URL, credentials or real Play traffic. */
export class FakePlayApi implements PlayPurchaseApi {
  calls = 0;
  readonly handlers = new Map<string, (query: PlayPurchaseQuery) => unknown | Promise<unknown>>();

  async lookup(query: PlayPurchaseQuery): Promise<unknown | null> {
    this.calls++;
    const handler = this.handlers.get(query.purchaseToken);
    return handler ? await handler(query) : null;
  }

  respond(token: string, value: unknown): void {
    this.handlers.set(token, () => value);
  }
}
