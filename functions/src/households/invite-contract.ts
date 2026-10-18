import { createHash, randomBytes } from 'node:crypto';
import { Timestamp } from 'firebase-admin/firestore';
import { compareTime } from '../models';

export const MAX_FAMILY_MEMBERS = 8;
export const MAX_PENDING_INVITES = 8;
export const INVITE_SECONDS = 7 * 24 * 60 * 60;
export const inviteCodes = ['VALID','EXPIRED','REVOKED','USED','IN_PROGRESS','SELF_INVITE','ALREADY_MEMBER',
  'ALREADY_IN_FAMILY','FAMILY_FULL','FAMILY_UNAVAILABLE','FAMILY_PREPARING','FAMILY_DISSOLVING',
  'OWNER_UNAVAILABLE','OWNER_NOT_PRO','ACCOUNT_UNAVAILABLE','ACCOUNT_NOT_READY','NOT_OWNER',
  'NOT_FOUND','INVALID_ARGUMENT','FEATURE_DISABLED','PENDING_LIMIT','INVITE_STATE_UNAVAILABLE',
  'RETRYABLE_UNAVAILABLE'] as const;
export type InviteCode = typeof inviteCodes[number];
export class FamilyInviteError extends Error {
  constructor(readonly code: InviteCode) { super(code); }
}
export const inviteIdPattern = /^[a-f0-9]{64}$/;
export const newInviteToken = () => randomBytes(32).toString('base64url');
export function hashInviteToken(raw: unknown): string {
  if (typeof raw !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(raw) ||
      Buffer.from(raw,'base64url').length !== 32 || Buffer.from(raw,'base64url').toString('base64url') !== raw)
    throw new FamilyInviteError('INVALID_ARGUMENT');
  return createHash('sha256').update(raw).digest('hex');
}
const uid = (v: unknown): v is string => typeof v==='string' && v.length>0 && v.length<=128 && !v.includes('/') && v.trim()===v;
export interface FamilyInvite {
  schemaVersion: 1; householdId: string; createdByUid: string;
  createdAt: Timestamp; expiresAt: Timestamp;
  status: 'PENDING'|'RESERVED'|'USED'|'REVOKED';
  operationId: string|null; usedAt: Timestamp|null; usedByUid: string|null;
}
export function readInvite(raw: unknown): FamilyInvite {
  const v=raw as FamilyInvite;
  if (!v || Object.keys(v).sort().join(',')!=='createdAt,createdByUid,expiresAt,householdId,operationId,schemaVersion,status,usedAt,usedByUid' ||
      v.schemaVersion!==1 || !uid(v.createdByUid) || typeof v.householdId!=='string' || !/^[A-Za-z0-9_-]{1,128}$/.test(v.householdId) ||
      !(v.createdAt instanceof Timestamp) || !(v.expiresAt instanceof Timestamp) ||
      v.expiresAt.seconds-v.createdAt.seconds!==INVITE_SECONDS || v.expiresAt.nanoseconds!==v.createdAt.nanoseconds ||
      !['PENDING','RESERVED','USED','REVOKED'].includes(v.status) ||
      (['PENDING','REVOKED'].includes(v.status) ? v.operationId!==null : !uid(v.operationId)) ||
      (v.status==='USED' ? !(v.usedAt instanceof Timestamp) || !uid(v.usedByUid) || compareTime(v.usedAt,v.createdAt)<0 : v.usedAt!==null || v.usedByUid!==null))
    throw new FamilyInviteError('INVITE_STATE_UNAVAILABLE');
  return v;
}
/** Bounded inventory and common write guard. No token/email/payload storage. */
export function readInviteSlots(raw: unknown): string[] {
  const v=raw as {schemaVersion:number;inviteIds:unknown[]};
  if (!v || Object.keys(v).sort().join(',')!=='inviteIds,schemaVersion' || v.schemaVersion!==1 || !Array.isArray(v.inviteIds) ||
      v.inviteIds.length>MAX_PENDING_INVITES || new Set(v.inviteIds).size!==v.inviteIds.length ||
      v.inviteIds.some(id=>typeof id!=='string'||!inviteIdPattern.test(id))) throw new FamilyInviteError('INVITE_STATE_UNAVAILABLE');
  return v.inviteIds as string[];
}
