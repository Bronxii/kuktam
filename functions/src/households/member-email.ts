import { Auth } from 'firebase-admin/auth';

export interface MemberEmail { exists: boolean; email: string|null }
export interface MemberEmailResolver { resolve(uids: readonly string[]): Promise<ReadonlyMap<string,MemberEmail>> }
/** Only verified membership UIDs may reach this adapter; never a callable input. */
export class AdminMemberEmailResolver implements MemberEmailResolver {
  constructor(private readonly auth: Pick<Auth,'getUsers'>) {}
  async resolve(uids: readonly string[]): Promise<ReadonlyMap<string,MemberEmail>> {
    if (!uids.length || uids.length>8 || new Set(uids).size!==uids.length) throw new Error('invalidMemberLookup');
    const result=await this.auth.getUsers(uids.map(uid=>({uid})));
    const requested=new Set(uids), values=new Map<string,MemberEmail>(uids.map(uid=>[uid,{exists:false,email:null}]));
    for(const user of result.users)if(requested.has(user.uid))values.set(user.uid,{exists:true,email:user.email || null});
    return values;
  }
}
export const emailIdentity=(value:MemberEmail|undefined)=>({email:value?.email??null,displayIdentity:value?.email||'Ismeretlen tag'});
