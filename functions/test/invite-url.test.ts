import {test} from 'node:test';
import assert from 'node:assert/strict';
import {familyInviteUrl,FAMILY_INVITE_ORIGIN} from '../src/households/invite-url';
for(const byte of [0,1,127,254,255])test(`8A canonical URL round-trips token bytes ${byte}`,()=>{
 const token=Buffer.alloc(32,byte).toString('base64url'),value=familyInviteUrl(token),url=new URL(value);
 assert.equal(url.origin,'https://kuktam-67768.web.app');assert.equal(url.protocol,'https:');assert.equal(url.pathname,'/family/invite');assert.equal(url.hash,'');assert.equal(url.username,'');assert.equal(url.password,'');
 assert.deepEqual([...url.searchParams],[['token',token]]);assert.equal(url.searchParams.get('token'),token);assert.equal(familyInviteUrl(token),value);
 assert.equal(value,`${FAMILY_INVITE_ORIGIN}/family/invite?token=${token}`);
});
test('8A distinct credentials produce distinct URLs without metadata or second credential',()=>{assert.notEqual(familyInviteUrl(Buffer.alloc(32,0).toString('base64url')),familyInviteUrl(Buffer.alloc(32,1).toString('base64url')));});
for(const value of ['', ' A'.repeat(43), 'A'.repeat(42)+'B', 'https://example.test'])test(`8A invalid credential length ${value.length} rejects without fake URL`,()=>{assert.throws(()=>familyInviteUrl(value),/INVALID_ARGUMENT/);});
