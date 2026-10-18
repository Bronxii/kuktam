import {test} from 'node:test';
import assert from 'node:assert/strict';
import {Timestamp} from 'firebase-admin/firestore';
import {parseRequest,newEpoch,newMutationId,revision,epochExpiry,EPOCH_MS} from '../src/shopping/mutation-contract';
const now=Timestamp.fromMillis(1800000000000),epoch=newEpoch(now);
const request=(payload:unknown)=>({schemaVersion:1,mutationId:newMutationId(epoch),actorUid:'u',householdId:'h',epoch,kind:'ADD',payloadJson:JSON.stringify(payload),submittedAt:now});
test('epoch and identity have bounded server expiry and collision resistant suffix',()=>{
 assert.equal(epochExpiry(epoch),now.toMillis()+EPOCH_MS);assert.equal(new Set(Array.from({length:1000},()=>newMutationId(epoch))).size,1000);
 assert.equal(revision(undefined),0);assert.throws(()=>revision(-1));
});
test('normalization preserves repository trim/lowercase kg/l behavior',()=>{
 for(const [unit,expected] of [['kg','g'],['l','ml'],['db','db']]){
 const r=request({type:'ADD',name:' ALMA ',quantity:2,unit});const p=parseRequest(r,'u',r.mutationId);
 assert.deepEqual(p.children,[{type:'ADD',name:'alma',quantity:unit==='db'?2:2000,unit:expected}]);}
});
for(const payload of [null,{},[],{type:'ADD',name:'x',quantity:0,unit:'g'},{type:'ADD',name:'x',quantity:-1,unit:'g'},
 {type:'ADD',name:'x',quantity:1,unit:' G '},{type:'ADD',name:'x',quantity:1,unit:'g',isChecked:true},
 {type:'ADD',name:'x'.repeat(201),quantity:1,unit:'g'},{type:'ADD',name:'x',quantity:1e300,unit:'kg'},
 {type:'DELETE',itemId:'../x',expectedRevision:0},{type:'SET_CHECKED',itemId:'x',expectedRevision:0,isChecked:'true'}]){
 test(`reject malformed payload ${JSON.stringify(payload).slice(0,85)}`,()=>{const r=request(payload);assert.throws(()=>parseRequest(r,'u',r.mutationId));});
}
test('strict envelope, actor, kind, ID/epoch and payload limits',()=>{
 const r=request({type:'ADD',name:'x',quantity:1,unit:'g'});
 for(const patch of [{status:'APPLIED'},{actorUid:'other'},{epoch:newEpoch(now)},{kind:'DELETE'},{submittedAt:0},{payloadJson:'x'.repeat(262145)}])assert.throws(()=>parseRequest({...r,...patch},'u',r.mutationId));
});
test('bulk validates all children before any effect; bounds and stable request hash',()=>{
 const r={...request({items:Array.from({length:200},()=>({type:'ADD',name:'x',quantity:1,unit:'g'}))}),kind:'BULK'};
 assert.equal(parseRequest(r,'u',r.mutationId).children.length,200);
 assert.throws(()=>parseRequest({...r,payloadJson:JSON.stringify({items:Array(201).fill({type:'ADD',name:'x',quantity:1,unit:'g'})})},'u',r.mutationId));
 const a=parseRequest(r,'u',r.mutationId).hash,b=parseRequest({...r,submittedAt:Timestamp.now()},'u',r.mutationId).hash;assert.equal(a,b);
});
