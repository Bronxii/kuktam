import { createHash } from 'node:crypto';
import { DocumentSnapshot } from 'firebase-admin/firestore';

const frame=(tag:string,value:Buffer|string)=>{const b=Buffer.isBuffer(value)?value:Buffer.from(value);return Buffer.concat([Buffer.from(`${tag}:${b.length}:`),b]);};
/** Canonical Firestore wire values, not lossy JS data(): integer/double stay distinct. */
export function canonicalValue(v:any):Buffer {
  const keys=Object.keys(v).filter(k=>k!=='valueType');
  if(keys.length!==1)throw new Error('invalidSnapshotValue');
  const k=keys[0]!,x=v[k];
  switch(k){
    case 'nullValue':return frame('null','');
    case 'booleanValue':return frame('bool',x?'1':'0');
    case 'integerValue':return frame('int',BigInt(x.toString()).toString());
    case 'doubleValue': {const b=Buffer.alloc(8);b.writeDoubleBE(Number(x));return frame('double',Number.isNaN(Number(x))?'NaN':b);}
    case 'timestampValue':return frame('time',`${x.seconds?.toString()??'0'}/${x.nanos??0}`);
    case 'stringValue':return frame('string',x);
    case 'bytesValue':return frame('bytes',typeof x==='string'?Buffer.from(x,'base64'):Buffer.from(x));
    case 'referenceValue':return frame('ref',x);
    case 'geoPointValue':return frame('geo',Buffer.concat([canonicalValue({doubleValue:x.latitude}),canonicalValue({doubleValue:x.longitude})]));
    case 'arrayValue':return frame('array',Buffer.concat((x.values??[]).map(canonicalValue)));
    case 'mapValue': {const f=x.fields??{};return frame('map',Buffer.concat(Object.keys(f).sort((a,b)=>Buffer.compare(Buffer.from(a),Buffer.from(b))).flatMap(key=>[frame('key',key),canonicalValue(f[key])])));}
    default:throw new Error('unsupportedSnapshotValue');
  }
}
export const digest=(v:Buffer|string)=>createHash('sha256').update(v).digest('hex');
export function sourceFingerprint(doc:DocumentSnapshot):string {
  // Pinned Admin SDK internal wire accessor: fail closed if its contract changes.
  const proto=(doc as unknown as {toDocumentProto():{fields:unknown}}).toDocumentProto();
  if(!doc.exists||!doc.updateTime||!proto.fields)throw new Error('snapshotUnavailable');
  return digest(Buffer.concat([frame('source-v1',doc.id),frame('update',`${doc.updateTime.seconds}/${doc.updateTime.nanoseconds}`),canonicalValue({mapValue:{fields:proto.fields}})]));
}
