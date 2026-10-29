// Local-only defect reproduction; PASS here means the reported defect is reproduced.
const assert=require('node:assert/strict');
const {spawn}=require('node:child_process');
const {createInterface}=require('node:readline');
require('../lib/test/emulator-guard').requireLocalEmulator(process.env);
if(process.env.FIREBASE_AUTH_EMULATOR_HOST!=='127.0.0.1:9098')throw Error('Local Auth required');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore}=require('firebase-admin/firestore');
const app=initializeApp({projectId:'demo-kuktam-local'},'review9b'),db=getFirestore(app);
const child=spawn(process.execPath,[require('node:path').resolve(__dirname,'family-qa-bridge.cjs')],{stdio:['pipe','pipe','ignore']});
const lines=createInterface({input:child.stdout})[Symbol.asyncIterator]();
let stage="start", sequence=0;
async function call(name,uid,data={}){stage=name+" #"+(++sequence);child.stdin.write(JSON.stringify({name,uid,data})+'\n');const {value,done}=await lines.next();assert.ok(!done);const r=JSON.parse(value);if(r.error)throw Object.assign(new Error(r.error.message),{code:r.error.code});return r.data;}
async function worker(n){for(let i=0;i<n;i++)await call('worker');}
(async()=>{try{
 await call('fixture');
 await db.doc('households/'+require('../lib/src/households/household-store').privateHouseholdId('owner')+'/shoppingItems/milk').update({revision:1});
 await call('signIn','owner');
 const first=await call('createFamilyShare','owner');await worker(5);
 assert.equal((await call('getFamilyShareState','owner')).role,'owner');
 const family=(await db.doc('users/owner').get()).get('familyHouseholdId');
 assert.equal((await db.doc('familyInviteSlots/'+family).get()).exists,false);
 await call('startFamilyDissolution','owner');await worker(60);
 try{assert.equal((await call('getFamilyShareState','owner')).familyActive,false);}catch(e){console.log((await db.collection('familyOperations').get()).docs.map(d=>({kind:d.get('kind'),status:d.get('status'),phase:d.get('phase'),outcome:d.get('lastOutcome')})));throw e;}
 console.log('PASS R2: fresh no-invite owner-only Family dissolves, missing slot index safely becomes empty.');
 assert.deepEqual((await db.doc('familyInviteSlots/'+family).get()).get('inviteIds'),[]);
 const again=await call('createFamilyShare','owner');await worker(5);
 assert.equal(again.operationId,first.operationId);assert.equal(again.outcome,'DONE');
 assert.equal((await call('getFamilyShareState','owner')).familyActive,false);
 console.log('REPRODUCED R1a: create after dissolution returns historical DONE; user remains private.');
 await db.doc('users/guest/entitlementGrants/pro').set(require('../lib/test/fixtures').grant());
 await call('signIn','guest');await call('createFamilyShare','guest');await worker(5);
 const invitation=await call('createFamilyInvite','guest');
 assert.equal((await call('previewFamilyInvite','owner',{token:invitation.token})).code,'VALID');
 await assert.rejects(call('acceptFamilyInvite','owner',{token:invitation.token,mode:'ADD'}),e=>e.message==='IN_PROGRESS');
 console.log('REPRODUCED R1b: former owner preview VALID, new JOIN rejected IN_PROGRESS by historical CREATE.');
 console.log('9B product readiness FAIL; no production writes; no CREATE-generation redesign attempted.');
 }finally{child.kill();await deleteApp(app);}})().catch(e=>{console.error(e.name, e.code || 'no-code', /^[A-Z_]+$/.test(e.message)?e.message:'redacted');console.error('Local reproduction did not complete at '+stage);process.exitCode=1;});
