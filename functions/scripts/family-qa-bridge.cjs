// Test-only stdio transport, never an exported server or deployed function.
const {initializeApp}=require('firebase-admin/app');
const {getFirestore,Timestamp}=require('firebase-admin/firestore');
const {requireLocalEmulator}=require('../lib/test/emulator-guard');
requireLocalEmulator(process.env);
if(process.env.FIREBASE_AUTH_EMULATOR_HOST!=='127.0.0.1:9098')throw Error('Local Auth emulator required');
const app=initializeApp({projectId:'demo-kuktam-local'},'qa9a'),db=getFirestore(app);
const auth=require('firebase-admin/auth').getAuth(app),sessions=new Map();
const {HouseholdStore,privateHouseholdId}=require('../lib/src/households/household-store');
const {FamilyCreateStore}=require('../lib/src/households/family-create');
const {FamilyInviteStore}=require('../lib/src/households/family-invites');
const {FamilyJoinStore}=require('../lib/src/households/family-join');
const {JoinTransferStore}=require('../lib/src/households/join-transfer');
const {MemberLeaveStore}=require('../lib/src/households/member-leave');
const {OwnerProLossStore}=require('../lib/src/households/owner-pro-loss');
const {ShoppingMutationStore}=require('../lib/src/shopping/mutation-store');
const {grant,now}=require('../lib/test/fixtures');
let ms=now.toMillis()+1000;
const clock=()=>Timestamp.fromMillis(ms);
const invites=()=>new FamilyInviteStore(db,{resolve:async uids=>new Map(uids.map(uid=>[uid,{exists:true,email:uid+'@example.test'}]))},clock);
const ih=require('../lib/src/households/invite-handler').familyInviteHandlers(invites);
const leave=()=>new MemberLeaveStore(db,clock);
const transfer=action=>require('../lib/src/households/join-transfer-handler').joinTransferHandler(()=>new JoinTransferStore(db,clock),action);
const handlers={
 createFamilyShare:require('../lib/src/households/family-handler').createFamilyHandler(()=>new FamilyCreateStore(db,clock)),
 createFamilyInvite:ih.create,previewFamilyInvite:ih.preview,getFamilyShareState:ih.state,
 acceptFamilyInvite:require('../lib/src/households/join-handler').acceptFamilyHandler(()=>new FamilyJoinStore(db,clock)),
 prepareFamilyJoinTransfer:transfer('prepare'),getFamilyJoinTransferState:transfer('state'),confirmFamilyJoinDelete:transfer('confirm'),cancelFamilyJoin:transfer('cancel'),
 leaveFamilyShare:require('../lib/src/households/member-leave-handler').memberLeaveHandler(leave),
 removeFamilyMember:require('../lib/src/households/member-leave-handler').ownerRemoveHandler(leave),
 startFamilyDissolution:require('../lib/src/households/owner-dissolution-handler').ownerDissolutionHandler(()=>new OwnerProLossStore(db,clock)),
};
async function dispatch(r){
 if(r.name==='fixture'){
  const reset=await fetch('http://127.0.0.1:8088/emulator/v1/projects/demo-kuktam-local/databases/(default)/documents',{method:'DELETE'});
  if(!reset.ok)throw Error('resetFailed');
  await fetch('http://127.0.0.1:9098/emulator/v1/projects/demo-kuktam-local/accounts',{method:'DELETE'});
  for(const uid of ['owner','guest']){await new HouseholdStore(db).ensure({uid});await auth.createUser({uid,email:uid+'@example.test',password:'LocalQA-only-123!',emailVerified:true});}
  await db.doc('users/owner/entitlementGrants/pro').set(grant());
  await db.doc('familyRuntime/config').set({creationEnabled:true,inviteCreationEnabled:true,joinReservationEnabled:true});
  await db.doc('shoppingRuntime/config').set({enabled:true});
  await db.doc(`households/${privateHouseholdId('owner')}/shoppingItems/milk`).set({name:'milk',quantity:1000,unit:'ml',isChecked:false,createdAt:now});
  return {};
 }
 if(r.name==='signIn'){
  const response=await fetch('http://127.0.0.1:9098/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=local-only',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:r.uid+'@example.test',password:'LocalQA-only-123!',returnSecureToken:true})});
  const body=await response.json();if(!response.ok)throw Error('localSignInFailed');
  const verified=await auth.verifyIdToken(body.idToken);if(verified.uid!==r.uid||!verified.email_verified)throw Error('authGate');sessions.set(r.uid,body.idToken);return {uid:verified.uid};
 }
 if(r.name==='seedPrivate'){
  const root=db.collection(`households/${privateHouseholdId('guest')}/shoppingItems`);
  await root.doc('milk').set({name:'Milk',quantity:2,unit:'l',isChecked:false,createdAt:now});
  await root.doc('bread').set({name:'Bread',quantity:1,unit:'db',isChecked:false,createdAt:now});return {};
 }
 if(r.name==='worker'){
  // Substitute scheduler dispatch only. The unchanged server engines own phases.
  ms+=300001;
  for(const doc of (await db.collection('familyOperations').where('status','==','READY').get()).docs){
   if(doc.get('kind')==='CREATE')await new FamilyCreateStore(db,clock).resume(doc.id);
   if(doc.get('kind')==='JOIN')await new FamilyJoinStore(db,clock).resume(doc.id);
  }
  await new OwnerProLossStore(db,clock).sweep();return {};
 }
 if(r.name==='privateCount')return (await db.collection(`households/${privateHouseholdId('guest')}/shoppingItems`).get()).size;
 if(r.name==='inspect'){
  const context=await new ShoppingMutationStore(db,clock).ensureContext({uid:r.uid});
  const items=(await db.collection(`households/${context.householdId}/shoppingItems`).get()).docs.map(d=>d.data());
  const privateCount=(await db.collection(`households/${privateHouseholdId(r.uid)}/shoppingItems`).get()).size;
  return {context,items,privateCount,privateId:privateHouseholdId(r.uid)};
 }
 if(!handlers[r.name])throw Error('unknownTestCommand');
 const token=sessions.get(r.uid);const verified=token?await auth.verifyIdToken(token):null;
 return handlers[r.name]({auth:verified?{uid:verified.uid}:null,data:r.data||{}});
}
// Never echo request, credential, URL or stack. Pipe is private test transport.
(async()=>{for await(const line of require('node:readline').createInterface({input:process.stdin})){
 try{const data=await dispatch(JSON.parse(line));process.stdout.write(JSON.stringify({data})+'\n');}
 catch(e){process.stdout.write(JSON.stringify({error:{code:e.code||'internal',message:e.code?e.message:'TEST_BRIDGE_FAILURE'}})+'\n');}
}})();
