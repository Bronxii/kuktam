// Local test harness only. Actual FlutterFire SDK -> emulator rules -> actual S1A
// processor. This listener substitutes event delivery, never business execution.
const http=require('node:http');
const {spawn}=require('node:child_process');
const path=require('node:path');
// Emulator-only Admin SDK must never probe a cloud metadata server.
process.env.METADATA_SERVER_DETECTION='none';
const {execFileSync}=require('node:child_process');
const h2a=process.env.KUKTAM_E2E_SCOPE==='H2A';
const h2b=process.env.KUKTAM_E2E_SCOPE==='H2B';
const h2c1=process.env.KUKTAM_E2E_SCOPE==='H2C1';
const h2c2a=process.env.KUKTAM_E2E_SCOPE==='H2C2A';
const adb=path.join(process.env.LOCALAPPDATA,'Android/Sdk/platform-tools/adb.exe');
if(h2a||h2b||h2c1||h2c2a){
 const avd=execFileSync(adb,['-s','emulator-5580','emu','avd','name'],{encoding:'utf8'});
 if(!avd.split('\n').map(s=>s.trim()).includes('Kuktam_H2A_Local'))throw Error('Dedicated H2A AVD required');
}
let crashReady=null;
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
let paused=h2b||h2c2a;const running=new Map(),queued=new Map();
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
   case '/crash-ready':
    if(!(h2a||h2b||h2c1)||!crashReady)throw Error('Unexpected crash request');
    crashReady();break;
   case '/process-selected':{
    if(!h2c2a||!paused||!Array.isArray(input.commands)||input.commands.length<1||input.commands.length>3||!['concurrent','ordered'].includes(input.mode))throw Error('Bounded paused H2C2A commands required');
    const refs=input.commands.map(c=>{
      if(!/^client-[ab]$/.test(c.uid)||typeof c.id!=='string'||! /^[A-Za-z0-9_-]+$/.test(c.id))throw Error('Invalid local command');
      return db.doc(`users/${c.uid}/shoppingMutations/${c.id}`);
    });
    const before=await db.getAll(...refs);
    if(before.some(d=>!d.exists))throw Error('All commands must arrive before processing');
    if(input.mode==='concurrent')await Promise.all(input.commands.map(c=>store.process(c.uid,c.id,1)));
    else for(const c of input.commands)await store.process(c.uid,c.id,1);
    result={receipts:(await db.getAll(...refs)).map(d=>({id:d.id,actorUid:d.get('actorUid'),status:d.get('status'),results:d.get('results')}))};break;
   }
   case '/step':{
    if(!h2b||!paused||!Number.isInteger(input.steps)||input.steps<1||input.steps>200||typeof input.id!=='string')throw Error('Paused bounded H2B step required');
    for(let n=input.steps;n>0;n-=20)await store.process(uid,input.id,Math.min(n,20));
    const d=await db.doc(`users/${uid}/shoppingMutations/${input.id}`).get();
    result={status:d.get('status'),cursor:d.get('cursor'),results:d.get('results')};break;
   }
   case '/setup':
    await db.doc('shoppingRuntime/config').set({enabled:true});
    for(const u of ['client-a','client-b']){
      try{await auth.createUser({uid:u,email:`${u}@example.invalid`,password:'local-emulator-only-123'});}
      catch(e){if(e.code!=='auth/uid-already-exists')throw e;}
      await households.ensure({uid:u});await store.ensureContext({uid:u});
    }break;
   case '/context':result=await store.ensureContext({uid});break;
   case '/gate':
    if(!h2c1||typeof input.enabled!=='boolean')throw Error('H2C1 local gate required');
    await db.doc('shoppingRuntime/config').set({enabled:input.enabled});break;
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
   case '/delete':{
    if(!(h2a||h2b))throw Error('Native fixture required');
    const c=await store.ensureContext({uid});
    const matches=await db.collection(`households/${c.householdId}/shoppingItems`).where('name','==',input.name).get();
    if(matches.size!==1)throw Error('One fixture target required');
    const d=matches.docs[0];
    const r={schemaVersion:1,actorUid:uid,...c,mutationId:newMutationId(c.epoch),kind:'DELETE',
     payloadJson:JSON.stringify({type:'DELETE',itemId:d.id,expectedRevision:d.get('revision')??0}),submittedAt:Timestamp.now()};
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
  for(const phase of h2c2a?['online']:h2c1?['death-transition','resume-transition','invalid-reopen']:h2b?['death-queued','death-partial','complete','reopen']:h2a?['single','death-add','resume-add','death-edit','resume-edit']:['main','restart']){
   const death=phase.startsWith('death-');
   let signal;
   const crash=new Promise(resolve=>{signal=resolve;});
   crashReady=death?signal:null;
   const code=await new Promise((resolve,reject)=>{
    const child=spawn('cmd.exe',['/d','/c',flutter,'test',h2c2a?'integration_test/shopping_h2c2a_e2e_test.dart':h2c1?'integration_test/shopping_h2c1_e2e_test.dart':h2b?'integration_test/shopping_h2b_e2e_test.dart':h2a?'integration_test/shopping_h2a_e2e_test.dart':'integration_test/shopping_mutation_e2e_test.dart','-d','emulator-5580','--no-uninstall',`--dart-define=SHOPPING_E2E_PHASE=${phase}`],{cwd:root,stdio:'inherit'});
    let killed=false,watchdog;
    if(death)crash.then(()=>{
     try{
      const pid=execFileSync(adb,['-s','emulator-5580','shell','pidof','com.bronxii.kuktam'],{encoding:'utf8'}).trim();
      if(!pid)throw Error('No application process');
      execFileSync(adb,['-s','emulator-5580','shell','am','force-stop','com.bronxii.kuktam']);
      let remaining='';
      try{remaining=execFileSync(adb,['-s','emulator-5580','shell','pidof','com.bronxii.kuktam'],{encoding:'utf8'}).trim();}catch(e){if(e.status!==1)throw e;}
      if(remaining)throw Error('Application survived force-stop');
      killed=true;
      console.log(`${h2c1?'H2C1':h2b?'H2B':'H2A'} ${phase}: abrupt am force-stop verified, prior PID ${pid}; no graceful close`);
      // Harness watchdog only: the killed Flutter test runner may await VM data.
      // It does not decide application correctness or retry any mutation.
      watchdog=setTimeout(()=>{try{execFileSync('taskkill',['/PID',String(child.pid),'/T','/F']);}catch{}},15000);
     }catch(e){reject(e);}
    });
    child.on('error',reject);child.on('exit',resolve);
    child.on('exit',()=>{clearTimeout(watchdog);if(death&&!killed)process.exitCode=1;});
   });
   crashReady=null;
   if((!death&&code!==0)||process.exitCode)throw Error(`Flutter E2E ${phase} failed (${code})`);
  }
 }catch(e){console.error(e.message);process.exitCode=1;}
 finally{stop();server.close();await Promise.allSettled([...running.values()]);await deleteApp(app);}
});
