import {hashInviteToken} from './invite-contract';
/** Verified in 8A0 Hosting metadata. No alternate origins or link credentials. */
export const FAMILY_INVITE_ORIGIN='https://kuktam-67768.web.app';
export function familyInviteUrl(token:string):string {
 hashInviteToken(token); // Reject noncanonical credentials using the existing contract.
 const url=new URL('/family/invite',FAMILY_INVITE_ORIGIN);
 url.searchParams.set('token',token);
 return url.href;
}
