import {Firestore,DocumentReference,Query} from 'firebase-admin/firestore';

export interface Counts {
 documentGets:number; missingDocuments:number; queryCalls:number;
 queryDocuments:number; emptyQueries:number; maxQueryDocuments:number;
 readCategories:Record<string,number>; queryCategories:Record<string,number>;
 attemptedWrites:number; committedWrites:number; writeCategories:Record<string,number>;
 transactionCalls:number; transactionAttempts:number; transactionRetries:number;
 readOnlyTransactions:number;
}
const fresh=():Counts=>({documentGets:0,missingDocuments:0,queryCalls:0,queryDocuments:0,
 emptyQueries:0,maxQueryDocuments:0,readCategories:{},queryCategories:{},attemptedWrites:0,
 committedWrites:0,writeCategories:{},transactionCalls:0,transactionAttempts:0,
 transactionRetries:0,readOnlyTransactions:0});
const bump=(map:Record<string,number>,key:string,n=1)=>{map[key]=(map[key]??0)+n;};
/** TEST ONLY. Delegates every operation to the actual SDK; no executor or data mock.
 * Counts logical SDK requests/results, not RPCs/index billing/rules evaluation.
 * No prototype patching; unwrapped fixture/assertion calls cannot enter counters. */
export class FirestoreMeter {
 readonly db:Firestore;
 private active:Counts|undefined;
 private originals=new WeakMap<object,object>();
 constructor(private readonly raw:Firestore,private readonly householdId:string){
  this.db=new Proxy(raw,{get:(target,key)=>{
   if(key==='runTransaction')return (callback:any,options?:any)=>this.transaction(callback,options);
   if(key==='getAll')return async(...refs:any[])=>{
    const snapshots=await (target.getAll as any)(...refs.map(r=>this.unwrap(r)));
    for(const snapshot of snapshots)this.read(snapshot);return snapshots;
   };
   if(['batch','bulkWriter','recursiveDelete'].includes(String(key)))return ()=>{throw new Error('Unsupported metered API');};
   const value=(target as any)[key];
   return typeof value==='function'?(...args:any[])=>this.wrap(value.apply(target,args)):value;
  }});
 }
 private unwrap(value:any):any{return value&&typeof value==='object'?(this.originals.get(value)??value):value;}
 private category(path:string):string{
  const p=path.split('/');
  if(p[0]==='accountLifecycle')return 'lifecycle';
  if(p[0]==='familyMemberships')return 'reverseMembership';
  if(p[0]==='familyOperations')return 'reservedJoinOperation';
  if(p[0]==='shoppingRuntime')return 'runtimeGate';
  if(p[0]==='shoppingMutationWork')return 'work';
  if(p[0]==='users')return p[2]==='shoppingMutations'?'commandReceipt':'user';
  if(p[0]==='households'){
   if(p[2]==='shoppingItems')return 'item';
   if(p[2]==='members')return p[1]===this.householdId?'membership':'fallbackMembership';
   return p[1]===this.householdId?'household':'fallbackHousehold';
  }
  return 'other';
 }
 private read(snapshot:any){
  const c=this.active;if(!c)return;
  if(Array.isArray(snapshot.docs)){
   c.queryCalls++;c.queryDocuments+=snapshot.size;c.emptyQueries+=Number(snapshot.empty);
   c.maxQueryDocuments=Math.max(c.maxQueryDocuments,snapshot.size);
   // Metadata only: verified for the pinned SDK; tests assert the categories.
   const collection=snapshot.query._queryOptions.collectionId;
   bump(c.queryCategories,collection==='shoppingItems'?'itemCandidates':collection==='shoppingMutationWork'?'dueWork':`other:${collection}`);
  }else{
   c.documentGets++;c.missingDocuments+=Number(!snapshot.exists);
   bump(c.readCategories,this.category(snapshot.ref.path));
  }
 }
 private wrap(value:any):any{
  if(!(value instanceof DocumentReference)&&!(value instanceof Query))return value;
  const proxy=new Proxy(value as any,{get:(target,key)=>{
   if(key==='get')return async(...args:any[])=>{const result=await target.get(...args);this.read(result);return result;};
   if(value instanceof DocumentReference&&['create','set','update','delete'].includes(String(key)))return async(...args:any[])=>{
    const c=this.active;if(c)c.attemptedWrites++;
    const result=await target[key](...args);
    if(c){c.committedWrites++;bump(c.writeCategories,this.category(target.path));}return result;
   };
   const v=target[key];return typeof v==='function'?(...args:any[])=>this.wrap(v.apply(target,args)):this.wrap(v);
  }});
  this.originals.set(proxy,value);return proxy;
 }
 private async transaction(callback:any,options:any){
  const c=this.active;if(!c)return this.raw.runTransaction(callback,options);
  c.transactionCalls++;let attempts=0,lastWrites:string[]=[];
  const result=await this.raw.runTransaction(async tx=>{
   attempts++;c.transactionAttempts++;if(attempts>1)c.transactionRetries++;
   const writes:string[]=[];lastWrites=writes;
   let proxy:any;
   proxy=new Proxy(tx,{get:(target,key)=>{
    if(key==='get')return async(ref:any)=>{const result=await (target.get as any)(this.unwrap(ref));this.read(result);return result;};
    if(key==='getAll')return async(...refs:any[])=>{const result=await (target.getAll as any)(...refs.map(r=>this.unwrap(r)));for(const snap of result)this.read(snap);return result;};
    if(['create','set','update','delete'].includes(String(key)))return (ref:any,...args:any[])=>{
     const rawRef=this.unwrap(ref);c.attemptedWrites++;writes.push(this.category(rawRef.path));
     (target as any)[key](rawRef,...args);return proxy;
    };
    const v=(target as any)[key];return typeof v==='function'?v.bind(target):v;
   }});
   return callback(proxy);
  },options);
  c.committedWrites+=lastWrites.length;for(const category of lastWrites)bump(c.writeCategories,category);
  if(!lastWrites.length)c.readOnlyTransactions++;
  return result;
 }
 async measure<T>(operation:()=>Promise<T>):Promise<{value:T;counts:Counts;readEquivalent:number}>{
  if(this.active)throw new Error('Nested measurement would contaminate counters');
  const counts=fresh();this.active=counts;
  try {const value=await operation();return {value,counts,readEquivalent:counts.documentGets+counts.queryDocuments+counts.emptyQueries};}
  finally {this.active=undefined;}
 }
}
