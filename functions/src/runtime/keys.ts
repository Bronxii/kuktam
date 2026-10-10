import { RuntimeBindingKeys } from '../billing/binding-key-provider';
import { runtimeConfig } from './config';
/** Secret JSON: version -> canonical base64 of >=32 random bytes. No file/env fallback. */
export function loadBindingKeys(value: string): RuntimeBindingKeys {
  try {
    if (!value || value.length > 16384) throw new Error();
    const raw: unknown = JSON.parse(value);
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) throw new Error();
    const entries = Object.entries(raw);
    if (!entries.length || entries.length > 16) throw new Error();
    const keys: Record<string, Uint8Array> = {};
    for (const [version, encoded] of entries) {
      if (!/^v[1-9][0-9]*$/.test(version) || typeof encoded !== 'string') throw new Error();
      const bytes = Buffer.from(encoded, 'base64');
      if (bytes.length < 32 || bytes.length > 128 || bytes.toString('base64') !== encoded) throw new Error();
      keys[version] = bytes;
    }
    try { return new RuntimeBindingKeys(runtimeConfig.hmacCurrentVersion, () => keys); }
    finally { for (const key of Object.values(keys)) key.fill(0); }
  } catch { throw new Error('configurationUnavailable'); }
}
