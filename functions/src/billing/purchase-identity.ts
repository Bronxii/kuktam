import { createHash } from 'node:crypto';
import { PACKAGE_NAME } from './play-purchase-api';
export function tokenHash(token: string): string { return createHash('sha256').update(PACKAGE_NAME).update('\0').update(token).digest('hex'); }
export function playGrantId(hash: string): string { return `play_${hash}`; }
