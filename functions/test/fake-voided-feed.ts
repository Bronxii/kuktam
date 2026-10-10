import { VoidedPurchaseFeed, VoidedFeedQuery } from '../src/jobs/voided-feed';
export class FakeVoidedFeed implements VoidedPurchaseFeed {
 calls: VoidedFeedQuery[]=[];
 handler:(q:VoidedFeedQuery)=>Promise<unknown>=async()=>({items:[],nextPageToken:null});
 async list(q:VoidedFeedQuery):Promise<unknown>{this.calls.push(q);return this.handler(q);}
}
