import { createHash } from 'crypto';
import { PREMIUM_THEMES } from './economyRules';

export type ProductKind = 'consumable' | 'non_consumable' | 'subscription';

export interface ProductDef {
  id: string;
  kind: ProductKind;
  /** Remote Config key holding the number of coins granted. */
  coinsKey?: 'coins_small_amount' | 'coins_medium_amount' | 'coins_large_amount';
}

/** Product ids must match Play Console (see SETUP.md). */
export const PRODUCTS: Record<string, ProductDef> = {
  remove_ads: { id: 'remove_ads', kind: 'non_consumable' },
  premium_themes: { id: 'premium_themes', kind: 'non_consumable' },
  coins_small: { id: 'coins_small', kind: 'consumable', coinsKey: 'coins_small_amount' },
  coins_medium: { id: 'coins_medium', kind: 'consumable', coinsKey: 'coins_medium_amount' },
  coins_large: { id: 'coins_large', kind: 'consumable', coinsKey: 'coins_large_amount' },
  neurorush_pro: { id: 'neurorush_pro', kind: 'subscription' },
};

/** The obfuscated account id the app attaches to every purchase. */
export function obfuscatedAccountId(uid: string): string {
  return createHash('sha256').update(`neurorush:${uid}`).digest('hex').slice(0, 64);
}

export function tokenKey(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

export type Verdict =
  | { ok: true; orderId: string | null; expiresAt?: number; needsAck: boolean; consumed?: boolean }
  | { ok: false; reason: string };

/** Checks a one-time product purchase returned by the Play Developer API. */
export function checkProduct(p: Record<string, unknown>, uid: string, kind: ProductKind): Verdict {
  if (p.purchaseState !== 0) return { ok: false, reason: p.purchaseState === 2 ? 'pending' : 'not_purchased' };
  const account = p.obfuscatedExternalAccountId as string | undefined;
  if (account && account !== obfuscatedAccountId(uid)) return { ok: false, reason: 'other_account' };
  const consumed = p.consumptionState === 1;
  return {
    ok: true,
    orderId: (p.orderId as string) ?? null,
    needsAck: kind === 'non_consumable' && p.acknowledgementState !== 1,
    consumed,
  };
}

const ACTIVE_STATES = ['SUBSCRIPTION_STATE_ACTIVE', 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD'];

/** Checks a subscriptionsv2 resource. */
export function checkSubscription(s: Record<string, unknown>, uid: string): Verdict {
  const account = (s.externalAccountIdentifiers as { obfuscatedExternalAccountId?: string } | undefined)?.obfuscatedExternalAccountId;
  if (account && account !== obfuscatedAccountId(uid)) return { ok: false, reason: 'other_account' };
  if (!ACTIVE_STATES.includes(s.subscriptionState as string)) return { ok: false, reason: 'inactive' };
  const items = (s.lineItems as { expiryTime?: string; productId?: string }[] | undefined) ?? [];
  const expiresAt = Math.max(0, ...items.map((i) => (i.expiryTime ? Date.parse(i.expiryTime) : 0)));
  if (!expiresAt || expiresAt < Date.now()) return { ok: false, reason: 'expired' };
  return {
    ok: true,
    orderId: (s.latestOrderId as string) ?? null,
    expiresAt,
    needsAck: s.acknowledgementState === 'ACKNOWLEDGEMENT_STATE_PENDING',
  };
}

/** Entitlement changes for a verified product. */
export function grantFor(def: ProductDef, coinAmounts: Record<string, number>): { removeAds?: boolean; themes?: string[]; coins?: number; pro?: boolean } {
  switch (def.id) {
    case 'remove_ads':
      return { removeAds: true };
    case 'premium_themes':
      return { themes: PREMIUM_THEMES };
    case 'neurorush_pro':
      return { pro: true };
    default:
      return { coins: coinAmounts[def.coinsKey!] ?? 0 };
  }
}
