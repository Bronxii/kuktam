import { test } from 'node:test';
import assert from 'node:assert/strict';
import { canonicalValue, digest } from '../src/households/join-snapshot';
import { readJoinCapacity } from '../src/households/join-capacity';
import { joinTransferHandler } from '../src/households/join-transfer-handler';

test('fingerprint encoding is typed, framed, stable and map-order independent',()=>{
  const a={mapValue:{fields:{z:{stringValue:'ab:c'},a:{integerValue:'01'}}}};
  const b={mapValue:{fields:{a:{integerValue:'1'},z:{stringValue:'ab:c'}}}};
  assert.deepEqual(canonicalValue(a),canonicalValue(b));
  const values=[{integerValue:'1'},{doubleValue:1},{stringValue:'1'},{booleanValue:true},{nullValue:0},{doubleValue:-0},{doubleValue:0},{doubleValue:NaN},{doubleValue:Infinity},
    {bytesValue:Buffer.from([1,2])},{referenceValue:'projects/demo/databases/(default)/documents/a/b'},
    {timestampValue:{seconds:'1',nanos:2}},{geoPointValue:{latitude:1,longitude:2}},{arrayValue:{values:[{integerValue:1}]}},{mapValue:{}}];
  assert.equal(new Set(values.map(v=>digest(canonicalValue(v)))).size,values.length);
  assert.throws(()=>canonicalValue({newUnknownType:'x'}));
  assert.throws(()=>canonicalValue({integerValue:'1',doubleValue:1}));
});
test('capacity accepts legacy and rejects unowned structural locks',()=>{
  assert.deepEqual(readJoinCapacity(undefined),{schemaVersion:1,operationIds:[]});
  const id='join_'+'a'.repeat(64);
  assert.equal(readJoinCapacity({schemaVersion:2,operationIds:[id],structuralOperationId:id}).structuralOperationId,id);
  assert.throws(()=>readJoinCapacity({schemaVersion:2,operationIds:[],structuralOperationId:id}));
  assert.throws(()=>readJoinCapacity({schemaVersion:2,operationIds:[]}));
});
test('backend consent boundary rejects unauthenticated requests and arbitrary routing fields',async()=>{
  const h=joinTransferHandler(()=>{throw new Error('mustNotResolve');},'confirm');
  await assert.rejects(h({data:{}}),(e:any)=>e.code==='unauthenticated');
  await assert.rejects(h({auth:{uid:'u'},data:{operationId:'x',inviteId:'y',actorUid:'victim'}}),(e:any)=>e.code==='invalid-argument');
});
