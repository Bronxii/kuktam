import type { Auth } from 'firebase-admin/auth';
import { AuthUserDeletionApi } from '../accounts/deletion-contract';
import { Diagnostics, diagnose } from './config';
/** Execution adapter only. Never expose directly; caller must own a verified Auth claim. */
export class FirebaseAdminAuthDeletionAdapter implements AuthUserDeletionApi {
 constructor(private readonly auth:Pick<Auth,'deleteUser'>,private readonly diagnostics?:Diagnostics){}
 async deleteUser(uid:string,o:{signal:AbortSignal}):Promise<'deleted'|'notFound'|'temporaryFailure'|'permanentFailure'>{
  if(typeof uid!=='string'||!uid||uid.length>128||uid.trim()!==uid||uid.includes('/')){diagnose(this.diagnostics,'authDelete','invalidArgument');return 'permanentFailure';}
  if(o.signal.aborted)return 'temporaryFailure';
  try{await this.auth.deleteUser(uid);return 'deleted';}
  catch(e){const code=(e as {code?:unknown})?.code;if(code==='auth/user-not-found')return 'notFound';
   const temporary=['auth/internal-error','app/network-error','app/network-timeout','auth/too-many-requests','ECONNRESET','ETIMEDOUT','EAI_AGAIN'].includes(code as string);
   diagnose(this.diagnostics,'authDelete',temporary?'retryableUnavailable':'configurationError');return temporary?'temporaryFailure':'permanentFailure';
  }
 }
}
