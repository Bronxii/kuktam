import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Timestamp } from 'firebase-admin/firestore';
import { readDeletion, defaultDeletionPolicy, validateDeletionPolicy } from '../src/accounts/deletion-contract';
const job={schemaVersion:1,operationId:'op',generation:2,stage:'GRANTS',authGone:false,leaseId:null,leaseUntil:null,nextAt:null,lastOutcome:null,updatedAt:Timestamp.fromMillis(1)};
test('strict deletion schema accepts valid progress',()=>{assert.equal(readDeletion(job).stage,'GRANTS');assert.ok(Object.isFrozen(readDeletion(job)));});
for(const change of [{schemaVersion:2},{stage:'ACTIVE'},{generation:0},{uid:'injected'},{leaseId:'orphan'},{authGone:'true'}])test(`strict deletion schema rejects ${Object.keys(change)[0]}`,()=>{assert.throws(()=>readDeletion({...job,...change}));});
test('deletion external timeout must be shorter than claim lease',()=>{validateDeletionPolicy(defaultDeletionPolicy);assert.throws(()=>validateDeletionPolicy({...defaultDeletionPolicy,ioTimeoutMs:120000}));});

import { requireRecentDeletionAuth } from '../src/accounts/deletion-gateway';
test('P0C legacy evidence defaults PENDING, v2 requires exact evidence',()=>{
 assert.equal(readDeletion(job).cleanupState,'PENDING');
 assert.equal(readDeletion({...job,schemaVersion:2,cleanupState:'VERIFIED'}).cleanupState,'VERIFIED');
 for(const extra of [{schemaVersion:3},{schemaVersion:2},{cleanupState:'VERIFIED'},{schemaVersion:2,cleanupState:true}])assert.throws(()=>readDeletion({...job,...extra}));
});
test('P0C recent auth uses trusted seconds, strict boundary and rejects future/missing',()=>{
 assert.equal(requireRecentDeletionAuth({uid:'u',authTimeSeconds:700},1000000).uid,'u');
 for(const auth of [null,{uid:'u',authTimeSeconds:699},{uid:'u',authTimeSeconds:1001},{uid:'u',authTimeSeconds:NaN}])assert.throws(()=>requireRecentDeletionAuth(auth,1000000));
});
