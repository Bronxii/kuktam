/** Runtime-injected Secret binding values only. No environment/file lookup or persistence. */
export interface BindingKeyProvider { readonly currentVersion:string; material(version:string):Uint8Array; }
export class RuntimeBindingKeys implements BindingKeyProvider {
 readonly currentVersion:string;
 #keys=new Map<string,Uint8Array>();
 constructor(currentVersion:string,load:()=>Readonly<Record<string,Uint8Array>>){
  if(!/^v[1-9][0-9]*$/.test(currentVersion))throw new Error('bindingKeyConfiguration');
  this.currentVersion=currentVersion;
  let keys:Readonly<Record<string,Uint8Array>>;try{keys=load();}catch{throw new Error('bindingKeyConfiguration');}
  if(!keys||typeof keys!=='object')throw new Error('bindingKeyConfiguration');
  for(const [version,key]of Object.entries(keys)){
   if(!/^v[1-9][0-9]*$/.test(version)||!(key instanceof Uint8Array)||key.byteLength<32)throw new Error('bindingKeyConfiguration');
   this.#keys.set(version,new Uint8Array(key));
  }
  if(!this.#keys.has(currentVersion))throw new Error('bindingKeyConfiguration');
 }
 material(version:string){const k=this.#keys.get(version);if(!k)throw new Error('bindingKeyUnavailable');return new Uint8Array(k);}
}
