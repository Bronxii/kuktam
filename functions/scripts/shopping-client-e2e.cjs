// Local test harness only. Actual FlutterFire SDK -> emulator rules -> actual S1A
// processor. This listener substitutes event delivery, never business execution.
const http=require('node:http');
const {spawn}=require('node:child_process');
const path=require('node:path');
if(process.env.FIRESTORE_EMULATOR_HOST!=='127.0.0.1:8088'||
   process.env.FIREBASE_AUTH_EMULATOR_HOST!=='127.0.0.1:9098'||
   process.env.GCLOUD_PROJECT!=='demo-kuktam-local')throw Error('Local emulators required');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore,Timestamp}=require('firebase-admin/firestore');
const {getAuth}=require('firebase-admin/auth');
const {ShoppingMutationStore,advanceShoppingEpoch}=require('../lib/src/shopping/mutation-store');
const {HouseholdStore}=require('../lib/src/households/household-store');
const {newMutationId}=require('../lib/src/shopping/mutation-contract');
const app=initializeApp({projectId:'demo-kuktam-local'}),db=getFirestore(app),auth=getAuth(app);
const store=new ShoppingMutationStore(db),households=new HouseholdStore(db);
let paused=false;const running=new Map(),queued=new Map();
async function execute(uid,id){
 const key=uid+'/'+id;if(paused||running.has(key))return;
 const work=(async()=>{let status;do{status=await store.process(uid,id,20);}while(status==='PROCESSING');})();
 running.set(key,work);try{await work;queued.delete(key);}finally{running.delete(key);}
}
const stop=db.collectionGroup('shoppingMutations').onSnapshot(snapshot=>{
 for(const change of snapshot.docChanges()){
  if(change.type==='removed')continue;
  const d=change.doc,s=d.get('status');
  if(s&&!['PROCESSING','FAILED_RETRYABLE'].includes(s))continue;
  const uid=d.ref.parent.parent.id;queued.set(uid+'/'+d.id,[uid,d.id]);
  execute(uid,d.id).catch(()=>{});
 }
});
const server=http.createServer(async(req,res)=>{
 try{
  if(req.method!=='POST')throw Error('POST required');
  let text='';for await(const part of req){text+=part;if(text.length>65536)throw Error('too large');}
  const input=JSON.parse(text||'{}'),uid=input.uid||'client-a';
  if(!/^client-[ab]$/.test(uid))throw Error('Fixture UID required');
  let result={};
  switch(req.url){
   case '/setup':
    await db.doc('shoppingRuntime/config').set({enabled:true});
    for(const u of ['client-a','client-b']){
      try{await auth.createUser({uid:u,email:`${u}@example.invalid`,password:'local-emulator-only-123'});}
      catch(e){if(e.code!=='auth/uid-already-exists')throw e;}
      await households.ensure({uid:u});await store.ensureContext({uid:u});
    }break;
   case '/context':result=await store.ensureContext({uid});break;
   case '/pause':paused=true;await Promise.all([...running.values()]);break;
   case '/resume':paused=false;for(const [u,id]of queued.values())execute(u,id).catch(()=>{});break;
   case '/epoch':{
    const c=await store.ensureContext({uid});await db.doc(`households/${c.householdId}`).update(advanceShoppingEpoch(Timestamp.now()));break;
   }
   case '/add':{
    const c=await store.ensureContext({uid});const r={schemaVersion:1,actorUid:uid,...c,
      mutationId:newMutationId(c.epoch),kind:'ADD',payloadJson:JSON.stringify({type:'ADD',name:input.name||'tea',quantity:input.quantity||500,unit:'db'}),submittedAt:Timestamp.now()};
    await store.submit({uid},r);await store.process(uid,r.mutationId);break;
   }
   case '/family':{
    const hid='test-family';await db.doc(`households/${hid}`).set({schemaVersion:2,kind:'family',state:'ACTIVE',operationId:null,ownerUid:'client-a',createdAt:Timestamp.now()});
    for(const [u,role]of [['client-a','owner'],['client-b','member']]){
      await db.doc(`users/${u}`).update({activeHouseholdId:hid,familyHouseholdId:hid});
      await db.doc(`households/${hid}/members/${u}`).set({role});
      await db.doc(`familyMemberships/${u}`).set({householdId:hid,role,state:'ACTIVE',operationId:null});
    }break;
   }
   default:throw Error('Unknown fixture operation');
  }
  res.writeHead(200,{'Content-Type':'application/json'});res.end(JSON.stringify(result));
 }catch(e){res.writeHead(500);res.end(JSON.stringify({error:e.code||e.message}));}
});
server.listen(8099,'127.0.0.1',async()=>{
 const flutter=process.env.KUKTAM_TEST_FLUTTER||'D:\\Flutter\\bin\\flutter.bat';
 const root=path.resolve(__dirname,'../..');
 try{
  for(const phase of ['main','restart']){
   const code=await new Promise((resolve,reject)=>{
    const child=spawn('cmd.exe',['/d','/c',flutter,'test','integration_test/shopping_mutation_e2e_test.dart','-d','emulator-5580','--no-uninstall',`--dart-define=SHOPPING_E2E_PHASE=${phase}`],{cwd:root,stdio:'inherit'});
    child.on('error',reject);child.on('exit',resolve);
   });
   if(code!==0)throw Error(`Flutter E2E ${phase} failed (${code})`);
  }
 }catch(e){console.error(e.message);process.exitCode=1;}
 finally{stop();server.close();await Promise.allSettled([...running.values()]);await deleteApp(app);}
});
