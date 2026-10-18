import { test } from 'node:test';
import assert from 'node:assert/strict';
import { defaultMaintenancePolicy as p, validatePolicy, nextActiveCheck, nextFailure, voidedWindow, ackDeadline, categories, bounded } from '../src/jobs/maintenance-policy';
import { workKey, readWork } from '../src/jobs/maintenance-store';
import { parseFeed } from '../src/jobs/voided-feed';
test('policy accepts safe defaults and rejects unbounded batches/unsafe timeout/lookback',()=>{
 validatePolicy(p); for(const override of [{pageSize:101},{ioTimeoutMs:120000},{voidedLookbackMs:31*86400000},{spread:NaN}]) assert.throws(()=>validatePolicy({...p,...override}));
});
test('retry starts at base, grows exponentially, caps',()=>{ assert.equal(nextFailure(1,1,p),300001); assert.equal(nextFailure(1,2,p),600001); assert.equal(nextFailure(1,100,p),1+p.unresolvedCapMs); });
test('daily recheck jitter spreads deterministic samples',()=>{assert.equal(nextActiveCheck(0,()=>0.5,p),86400000); assert.ok(nextActiveCheck(0,()=>0,p)<nextActiveCheck(0,()=>0.99,p)); assert.throws(()=>nextActiveCheck(0,()=>1,p));});
test('voided lookback is bounded technical window',()=>{assert.deepEqual(voidedWindow(40*86400000),{startMs:10*86400000,endMs:40*86400000}); assert.equal(voidedWindow(1).startMs,0);});
test('unknown completion time never invents deadline',()=>{assert.equal(ackDeadline(null),null);assert.equal(ackDeadline(1),259200001);});
test('priority is explicit and deterministic',()=>{assert.deepEqual(categories,['ack','expiredInbox','retryInbox','unresolvedInbox','voided','active','grants','tokens','deletion','family','shopping']);});
test('work identity separates categories and tuple boundaries',()=>{assert.notEqual(workKey('a','b:c'),workKey('a:b','c')); assert.equal(workKey('a','b'),workKey('a','b'));});
test('strict work reader rejects corrupt state',()=>{assert.throws(()=>readWork({schemaVersion:99}));});
test('feed bounded parser rejects excess and malformed entries',()=>{assert.throws(()=>parseFeed({items:[{purchaseToken:'x',voidedTimeMs:1}],nextPageToken:null},0));assert.throws(()=>parseFeed({items:[{}],nextPageToken:null},1));});
test('external timeout aborts without infinite retries',async()=>{let signal:AbortSignal|undefined;await assert.rejects(bounded(async s=>{signal=s;return new Promise(()=>{});},5));assert.equal(signal!.aborted,true);});
