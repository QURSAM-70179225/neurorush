import { createVerify } from 'crypto';

/** Verification of AdMob server-side verification (SSV) callbacks. */
type KeyFetcher = () => Promise<Record<string, string>>;

let keysUrl = 'https://www.gstatic.com/admob/reward/verifier-keys.json';
let keyCache: { at: number; keys: Record<string, string> } | null = null;

export function setKeysUrl(url: string): void {
  if (url !== keysUrl) keyCache = null;
  keysUrl = url;
}

let fetchKeys: KeyFetcher = async () => {
  if (keyCache && Date.now() - keyCache.at < 6 * 3600_000) return keyCache.keys;
  const res = await fetch(keysUrl);
  const body = (await res.json()) as { keys: { keyId: number; pem: string }[] };
  const keys = Object.fromEntries(body.keys.map((k) => [String(k.keyId), k.pem]));
  keyCache = { at: Date.now(), keys };
  return keys;
};

export function setKeyFetcher(f: KeyFetcher): void {
  fetchKeys = f;
}
/**
 * Verifies an AdMob server-side verification (SSV) callback. The signed
 * message is the query string up to (excluding) "&signature=".
 */
export async function verifySsv(rawQuery: string): Promise<URLSearchParams | null> {
  const sigAt = rawQuery.indexOf('&signature=');
  if (sigAt < 0) return null;
  const message = rawQuery.slice(0, sigAt);
  const params = new URLSearchParams(rawQuery);
  const signature = params.get('signature');
  const keyId = params.get('key_id');
  if (!signature || !keyId) return null;
  const pem = (await fetchKeys())[keyId];
  if (!pem) return null;
  const ok = createVerify('SHA256').update(message).verify(pem, Buffer.from(signature, 'base64url'));
  return ok ? params : null;
}

