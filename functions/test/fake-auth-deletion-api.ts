import { AuthUserDeletionApi } from '../src/accounts/deletion-contract';
export class FakeAuthDeletionApi implements AuthUserDeletionApi {
 calls=0;readonly deleted=new Set<string>();
 handler:AuthUserDeletionApi['deleteUser']=async uid=>{if(this.deleted.has(uid))return 'notFound';this.deleted.add(uid);return 'deleted';};
 async deleteUser(uid:string,options:{signal:AbortSignal}){this.calls++;return this.handler(uid,options);}
}
