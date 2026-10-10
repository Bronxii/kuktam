import { BindingKeyProvider, RuntimeBindingKeys } from './binding-key-provider';
import { PACKAGE_NAME } from './play-purchase-api';
import { createHmac, timingSafeEqual } from 'node:crypto';
import { VerificationError } from './errors';

/** Supplied by a future authenticated transport, NEVER by request JSON. */
export interface AuthContext { readonly uid: string }

export function authenticatedUid(context: AuthContext | null | undefined): string {
  if (!context || typeof context.uid !== 'string' || context.uid.length === 0 ||
    context.uid.length > 128 || context.uid.includes('/') || context.uid.trim() !== context.uid) {
    throw new VerificationError('unauthenticated');
  }
  return context.uid;
}

/** Inject a stable server secret (>=256 random bits), never ship it to Flutter.
 * No default key: deployment/key provisioning and rotation are outside N3.
 */
export class AccountBinding {
  readonly keyVersion:string;
  #provider:BindingKeyProvider;
  constructor(key:Uint8Array|BindingKeyProvider){
    this.#provider=key instanceof Uint8Array?new RuntimeBindingKeys('v1',()=>({v1:key})):key;
    this.keyVersion=this.#provider.currentVersion;
    if(!/^v[1-9][0-9]*$/.test(this.keyVersion))throw new Error('bindingKeyConfiguration');
    const material=this.#provider.material(this.keyVersion);
    if(!(material instanceof Uint8Array)||material.length<32)throw new Error('bindingKeyConfiguration');
    material.fill(0);
  }
  private derive(context:AuthContext|null|undefined,version:string){
    const uid=authenticatedUid(context);
    if(!/^v[1-9][0-9]*$/.test(version))throw new Error('bindingKeyUnavailable');
    let key:Uint8Array;
    try{key=this.#provider.material(version);}catch{throw new Error('bindingKeyUnavailable');}
    if(!(key instanceof Uint8Array)||key.length<32)throw new Error('bindingKeyConfiguration');
    try{return version+'_'+createHmac('sha256',key).update('kuktam:'+PACKAGE_NAME+':account:'+version+'\0').update(uid).digest('base64url');}
    finally{key.fill(0);}
  }
  forAuthenticatedAccount(context:AuthContext|null|undefined){return this.derive(context,this.keyVersion);}
  matches(context:AuthContext,actual:string|null){
    if(actual===null||!/^v[1-9][0-9]*_[A-Za-z0-9_-]{43}$/.test(actual))return false;
    const expected=Buffer.from(this.derive(context,actual.split('_')[0]!)),supplied=Buffer.from(actual);
    return expected.length===supplied.length&&timingSafeEqual(expected,supplied);
  }
}
