import { createSign, generateKeyPairSync } from 'crypto';
import { setKeyFetcher, verifySsv } from '../src/ssv';
import { checkProduct, checkSubscription, grantFor, obfuscatedAccountId, PRODUCTS } from '../src/billingRules';
import { addDays, advanceStreak, ECONOMY_DEFAULTS, localDayOf, parseRewardCustomData, proActive } from '../src/economyRules';

describe('server streaks', () => {
  const s0 = { current: 0, best: 0, lastDay: null };
  test('first day, next day, same day', () => {
    const a = advanceStreak(s0, '2026-11-01', 1);
    expect(a.streak).toEqual({ current: 1, best: 1, lastDay: '2026-11-01' });
    const b = advanceStreak(a.streak, '2026-11-02', 1);
    expect(b.streak.current).toBe(2);
    expect(advanceStreak(b.streak, '2026-11-02', 1).streak.current).toBe(2);
  });
  test('freezes cover missed days, otherwise the streak restarts', () => {
    const s = { current: 5, best: 5, lastDay: '2026-11-01' };
    expect(advanceStreak(s, '2026-11-03', 1)).toMatchObject({ streak: { current: 6 }, freezes: 0, freezesUsed: 1 });
    expect(advanceStreak(s, '2026-11-04', 1)).toMatchObject({ streak: { current: 1, best: 5 }, freezes: 1, freezesUsed: 0 });
    expect(advanceStreak(s, '2026-11-04', 2)).toMatchObject({ streak: { current: 6 }, freezes: 0, freezesUsed: 2 });
  });
  test('a freeze is earned every 7 days, up to the cap', () => {
    const s = { current: 6, best: 6, lastDay: '2026-11-06' };
    expect(advanceStreak(s, '2026-11-07', 0)).toMatchObject({ freezes: 1, freezeEarned: true });
    expect(advanceStreak(s, '2026-11-07', 3)).toMatchObject({ freezes: 3, freezeEarned: false });
  });
  test('late uploads of older rounds do not change the streak', () => {
    const s = { current: 4, best: 9, lastDay: '2026-11-10' };
    expect(advanceStreak(s, '2026-11-08', 1).streak).toEqual(s);
  });
  test('local days and month boundaries', () => {
    expect(localDayOf(Date.UTC(2026, 10, 8, 20), 300)).toBe('2026-11-09');
    expect(addDays('2026-02-28', 1)).toBe('2026-03-01');
  });
});

describe('rewards', () => {
  test('custom data parsing', () => {
    expect(parseRewardCustomData('streak_freeze:abcdef12-34')).toEqual({ reward: 'streak_freeze', nonce: 'abcdef12-34', sessionId: null });
    expect(parseRewardCustomData('double_xp:abcdef1234:session-123')).toMatchObject({ reward: 'double_xp', sessionId: 'session-123' });
    expect(parseRewardCustomData('coins:abcdef1234')).toBeNull();
    expect(parseRewardCustomData('streak_freeze:x')).toBeNull();
    expect(parseRewardCustomData('streak_freeze:abcdef1234:<script>')).toBeNull();
  });
  test('pro needs a future expiry', () => {
    const now = Date.now();
    expect(proActive({ pro: true, proExpiresAt: now + 1000 }, now)).toBe(true);
    expect(proActive({ pro: true, proExpiresAt: now - 1 }, now)).toBe(false);
    expect(proActive({ pro: false, proExpiresAt: now + 1000 }, now)).toBe(false);
    expect(proActive(undefined, now)).toBe(false);
  });
});

describe('billing checks', () => {
  const uid = 'user-1';
  const acct = obfuscatedAccountId(uid);
  test('one-time products', () => {
    expect(checkProduct({ purchaseState: 0, acknowledgementState: 0, obfuscatedExternalAccountId: acct, orderId: 'GPA.1' }, uid, 'non_consumable'))
      .toEqual({ ok: true, orderId: 'GPA.1', needsAck: true, consumed: false });
    expect(checkProduct({ purchaseState: 2 }, uid, 'consumable')).toEqual({ ok: false, reason: 'pending' });
    expect(checkProduct({ purchaseState: 1 }, uid, 'consumable')).toEqual({ ok: false, reason: 'not_purchased' });
    expect(checkProduct({ purchaseState: 0, obfuscatedExternalAccountId: obfuscatedAccountId('thief') }, uid, 'consumable'))
      .toEqual({ ok: false, reason: 'other_account' });
    expect(checkProduct({ purchaseState: 0, consumptionState: 1 }, uid, 'consumable')).toMatchObject({ ok: true, consumed: true });
  });
  test('subscriptions', () => {
    const future = new Date(Date.now() + 30 * 86400_000).toISOString();
    const active = { subscriptionState: 'SUBSCRIPTION_STATE_ACTIVE', lineItems: [{ expiryTime: future }], acknowledgementState: 'ACKNOWLEDGEMENT_STATE_PENDING', latestOrderId: 'GPA.2' };
    expect(checkSubscription(active, uid)).toMatchObject({ ok: true, needsAck: true, expiresAt: Date.parse(future) });
    expect(checkSubscription({ ...active, subscriptionState: 'SUBSCRIPTION_STATE_EXPIRED' }, uid)).toEqual({ ok: false, reason: 'inactive' });
    expect(checkSubscription({ ...active, lineItems: [{ expiryTime: '2020-01-01T00:00:00Z' }] }, uid)).toEqual({ ok: false, reason: 'expired' });
    expect(checkSubscription({ ...active, externalAccountIdentifiers: { obfuscatedExternalAccountId: 'x' } }, uid)).toEqual({ ok: false, reason: 'other_account' });
  });
  test('grants', () => {
    expect(grantFor(PRODUCTS.coins_medium, ECONOMY_DEFAULTS)).toEqual({ coins: 1200 });
    expect(grantFor(PRODUCTS.remove_ads, ECONOMY_DEFAULTS)).toEqual({ removeAds: true });
    expect(grantFor(PRODUCTS.premium_themes, ECONOMY_DEFAULTS).themes).toHaveLength(3);
    expect(grantFor(PRODUCTS.neurorush_pro, ECONOMY_DEFAULTS)).toEqual({ pro: true });
  });
});

describe('AdMob SSV signatures', () => {
  const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const pem = publicKey.export({ type: 'spki', format: 'pem' }).toString();
  beforeAll(() => setKeyFetcher(async () => ({ '42': pem })));

  function signed(query: string): string {
    const sig = createSign('SHA256').update(query).sign(privateKey).toString('base64url');
    return `${query}&signature=${sig}&key_id=42`;
  }
  const q = 'ad_network=5450213213286189855&ad_unit=1234&custom_data=streak_freeze%3Aabcdef1234&reward_amount=1&reward_item=Reward&timestamp=1700000000000&transaction_id=tx1&user_id=u1';

  test('valid signature is accepted', async () => {
    const p = await verifySsv(signed(q));
    expect(p?.get('custom_data')).toBe('streak_freeze:abcdef1234');
  });
  test('tampered payload, unknown key or missing signature is rejected', async () => {
    expect(await verifySsv(signed(q).replace('user_id=u1', 'user_id=u2'))).toBeNull();
    expect(await verifySsv(signed(q).replace('key_id=42', 'key_id=7'))).toBeNull();
    expect(await verifySsv(q)).toBeNull();
  });
});
