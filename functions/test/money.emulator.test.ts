/**
 * Purchases, rewarded ads, server streaks and account deletion on the
 * emulators, with a mock Google Play Developer API and AdMob key server.
 */
import { createHash, createSign, generateKeyPairSync } from 'crypto';
import { createServer, Server } from 'http';
import { initializeApp, getApps } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';

const PROJECT = 'demo-neurorush';
const FN = `http://127.0.0.1:5001/${PROJECT}/asia-south1`;
const AUTH = 'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1';
if (getApps().length === 0) initializeApp({ projectId: PROJECT });
const db = getFirestore();
jest.setTimeout(60000);

const acct = (uid: string) => createHash('sha256').update(`neurorush:${uid}`).digest('hex').slice(0, 64);

// --- mock Play API + AdMob keys ------------------------------------------------
const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
const products: Record<string, Record<string, unknown>> = {};
const subs: Record<string, Record<string, unknown>> = {};
const playCalls: string[] = [];
let server: Server;
beforeAll(async () => {
  server = createServer((req, res) => {
    const url = req.url ?? '';
    playCalls.push(`${req.method} ${url}`);
    const send = (code: number, body: unknown) => {
      res.writeHead(code, { 'content-type': 'application/json' });
      res.end(JSON.stringify(body));
    };
    if (url === '/admob-keys.json') return send(200, { keys: [{ keyId: 77, pem: publicKey.export({ type: 'spki', format: 'pem' }).toString() }] });
    const m = url.match(/tokens\/([^/:]+)(:\w+)?$/);
    const token = m ? decodeURIComponent(m[1]) : '';
    if (req.method === 'POST') {
      if (m?.[2] === ':consume' && products[token]) products[token].consumptionState = 1;
      if (m?.[2] === ':acknowledge' && products[token]) products[token].acknowledgementState = 1;
      return send(200, {});
    }
    const body = url.includes('subscriptionsv2') ? subs[token] : products[token];
    return body ? send(200, body) : send(404, { error: 'not found' });
  });
  await new Promise<void>((r) => server.listen(4598, '127.0.0.1', () => r()));
});
afterAll(() => new Promise((r) => server.close(r)));

type User = { uid: string; token: string };
async function newUser(): Promise<User> {
  const r = await fetch(`${AUTH}/accounts:signUp?key=fake`, { method: 'POST', body: JSON.stringify({ returnSecureToken: true }), headers: { 'content-type': 'application/json' } });
  const j = (await r.json()) as { localId: string; idToken: string };
  return { uid: j.localId, token: j.idToken };
}
async function call<T = Record<string, unknown>>(name: string, u: User, data: unknown = {}) {
  const r = await fetch(`${FN}/${name}`, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${u.token}` }, body: JSON.stringify({ data }) });
  return (await r.json()) as { result?: T; error?: { status: string; message: string } };
}
const user = async (uid: string) => (await db.doc(`users/${uid}`).get()).data() ?? {};
let n = 0;
const tok = () => `tok-${Date.now()}-${++n}-abcdefghij`;

test('purchases: verified once with Google Play, acknowledged/consumed, never trusted from the app', async () => {
  const a = await newUser();
  const b = await newUser();

  const ads = tok();
  products[ads] = { purchaseState: 0, acknowledgementState: 0, obfuscatedExternalAccountId: acct(a.uid), orderId: 'GPA.1' };
  const r1 = await call<{ status: string; removeAds: boolean }>('verifyPurchase', a, { productId: 'remove_ads', purchaseToken: ads });
  expect(r1.result).toMatchObject({ status: 'granted', removeAds: true });
  expect(playCalls.some((c) => c.includes(`${ads}:acknowledge`))).toBe(true);

  const coins = tok();
  products[coins] = { purchaseState: 0, consumptionState: 0, obfuscatedExternalAccountId: acct(a.uid), orderId: 'GPA.2' };
  const r2 = await call<{ coins: number }>('verifyPurchase', a, { productId: 'coins_medium', purchaseToken: coins });
  expect(r2.result?.coins).toBe(1200);
  expect(products[coins].consumptionState).toBe(1);
  // Replaying the same purchase grants nothing more.
  const r3 = await call<{ status: string; coins: number }>('verifyPurchase', a, { productId: 'coins_medium', purchaseToken: coins });
  expect(r3.result).toMatchObject({ status: 'already', coins: 1200 });
  // Another account cannot use it.
  expect((await call('verifyPurchase', b, { productId: 'coins_medium', purchaseToken: coins })).error?.status).toBe('PERMISSION_DENIED');

  const stolen = tok();
  products[stolen] = { purchaseState: 0, consumptionState: 0, obfuscatedExternalAccountId: acct('someone-else') };
  expect((await call('verifyPurchase', a, { productId: 'coins_large', purchaseToken: stolen })).error?.status).toBe('PERMISSION_DENIED');
  const pending = tok();
  products[pending] = { purchaseState: 2 };
  expect((await call('verifyPurchase', a, { productId: 'coins_small', purchaseToken: pending })).error?.status).toBe('FAILED_PRECONDITION');
  expect((await call('verifyPurchase', a, { productId: 'coins_small', purchaseToken: 'unknown-token-123' })).error?.status).toBe('NOT_FOUND');
  expect((await call('verifyPurchase', a, { productId: 'free_money', purchaseToken: ads })).error?.status).toBe('INVALID_ARGUMENT');

  const sub = tok();
  const expiry = new Date(Date.now() + 30 * 86400_000).toISOString();
  subs[sub] = { subscriptionState: 'SUBSCRIPTION_STATE_ACTIVE', acknowledgementState: 'ACKNOWLEDGEMENT_STATE_PENDING', lineItems: [{ productId: 'neurorush_pro', expiryTime: expiry }], externalAccountIdentifiers: { obfuscatedExternalAccountId: acct(a.uid) } };
  const r4 = await call<{ pro: boolean; proExpiresAt: number }>('verifyPurchase', a, { productId: 'neurorush_pro', purchaseToken: sub });
  expect(r4.result).toMatchObject({ pro: true, proExpiresAt: Date.parse(expiry) });
  expect(playCalls.some((c) => c.includes(`subscriptions/neurorush_pro/tokens/${sub}:acknowledge`))).toBe(true);

  // Cancellation arrives as a real-time developer notification.
  subs[sub] = { ...subs[sub], subscriptionState: 'SUBSCRIPTION_STATE_EXPIRED' };
  const data = Buffer.from(JSON.stringify({ subscriptionNotification: { purchaseToken: sub, notificationType: 13 } })).toString('base64');
  await fetch(`http://127.0.0.1:8085/v1/projects/${PROJECT}/topics/play-billing:publish`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ messages: [{ data }] }) });
  let pro = true;
  for (let i = 0; i < 30 && pro; i++) {
    await new Promise((r) => setTimeout(r, 300));
    pro = (await user(a.uid)).entitlements?.pro;
  }
  expect(pro).toBe(false);

  // Client cannot grant itself anything (rules), and coins buy items server-side.
  const spend = await call<{ coins: number; freezes: number }>('spendCoins', a, { item: 'streak_freeze' });
  expect(spend.result).toMatchObject({ coins: 1100 });
  expect((await call<{ coins: number }>('spendCoins', a, { item: 'theme:neon_ocean' })).result?.coins).toBe(800);
  expect((await call('spendCoins', a, { item: 'theme:neon_ocean' })).error?.status).toBe('ALREADY_EXISTS');
  expect((await call('spendCoins', b, { item: 'theme:neon_pulse' })).error?.status).toBe('FAILED_PRECONDITION');
});

function ssvUrl(uid: string, customData: string, txId: string): string {
  const q = `ad_network=5450213213286189855&ad_unit=1&custom_data=${encodeURIComponent(customData)}&reward_amount=1&reward_item=Reward&timestamp=${Date.now()}&transaction_id=${txId}&user_id=${uid}`;
  const sig = createSign('SHA256').update(q).sign(privateKey).toString('base64url');
  return `${FN}/admobSsv?${q}&signature=${sig}&key_id=77`;
}

test('rewarded ads: only AdMob-verified rewards are granted, once', async () => {
  const u = await newUser();
  // Claim before AdMob's callback: not yet.
  expect((await call('claimAdReward', u, { nonce: 'nonce-freeze-1' })).error?.status).toBe('NOT_FOUND');
  // Forged callback (bad signature) is refused.
  const forged = ssvUrl(u.uid, 'streak_freeze:nonce-freeze-1', 'tx-f').replace(`user_id=${u.uid}`, 'user_id=attacker');
  expect((await fetch(forged)).status).toBe(400);

  expect((await fetch(ssvUrl(u.uid, 'streak_freeze:nonce-freeze-1', `tx-${u.uid}-1`))).status).toBe(200);
  expect((await fetch(ssvUrl(u.uid, 'streak_freeze:nonce-freeze-1', `tx-${u.uid}-1`))).status).toBe(200); // AdMob retry
  const c1 = await call<{ applied: boolean }>('claimAdReward', u, { nonce: 'nonce-freeze-1' });
  expect(c1.result).toMatchObject({ reward: 'streak_freeze', applied: true });
  expect((await user(u.uid)).freezes).toBe(1);
  expect((await call<{ applied: boolean; reason: string }>('claimAdReward', u, { nonce: 'nonce-freeze-1' })).result).toMatchObject({ applied: false, reason: 'already_claimed' });

  // Double XP for a round that has not been uploaded yet.
  const sessionId = `dxp-${Date.now()}-abc`;
  await fetch(ssvUrl(u.uid, `double_xp:nonce-dxp-123:${sessionId}`, `tx-${u.uid}-2`));
  expect((await call<{ applied: boolean }>('claimAdReward', u, { nonce: 'nonce-dxp-123' })).result?.applied).toBe(true);
  const s = { id: sessionId, gameId: 'speed_math', score: 1200, correct: 20, wrong: 0, maxCombo: 20, maxLevel: 5, avgReactionMs: 900, bestReactionMs: 400, playedAt: Date.now() - 1000, durationSeconds: 60 };
  const sub = await call<{ xp: number; totalXp: number }>('submitGameSession', u, { session: s, tzOffsetMinutes: 300 });
  expect(sub.result!.xp).toBe(sub.result!.totalXp);
  expect((await db.doc(`gameSessions/${sessionId}`).get()).data()).toMatchObject({ boosted: true, xp: sub.result!.xp });
  expect(sub.result!.xp).toBe(2 * (60 + 15 + 20)); // (1200/20 + 1★·15 + accuracy bonus) × 2

  // Extra life only after game over, once per run.
  await db.doc(`users/${u.uid}`).set({ endless: { lives: 0, run: 4 } }, { merge: true });
  await fetch(ssvUrl(u.uid, 'extra_life:nonce-life-1', `tx-${u.uid}-3`));
  expect((await call<{ applied: boolean }>('claimAdReward', u, { nonce: 'nonce-life-1' })).result?.applied).toBe(true);
  expect((await user(u.uid)).endless).toMatchObject({ lives: 1, revived: true, run: 4 });
});

test('server streak counts local days and uses freezes', async () => {
  const u = await newUser();
  const day = 86400_000;
  const base = Date.now() - 5 * day;
  const play = async (t: number, id: string) =>
    call('submitGameSession', u, {
      session: { id, gameId: 'color_clash', score: 600, correct: 20, wrong: 2, maxCombo: 8, maxLevel: 4, avgReactionMs: 900, bestReactionMs: 450, playedAt: t, durationSeconds: 60 },
      tzOffsetMinutes: 300,
    });
  await play(base, `st-${base}-a`);
  await play(base + day, `st-${base}-b`);
  await play(base + 3 * day, `st-${base}-c`); // one missed day: new players start with 1 freeze
  expect(await user(u.uid)).toMatchObject({ currentStreak: 3, bestStreak: 3, freezes: 0 });
  await play(base + 5 * day, `st-${base}-d`); // missed again, no freeze left
  expect(await user(u.uid)).toMatchObject({ currentStreak: 1, bestStreak: 3 });
});

test('account deletion removes the player everywhere', async () => {
  const a = await newUser();
  const b = await newUser();
  const name = `del${Date.now() % 1000000}`;
  await call('claimUsername', a, { username: name });
  await call('submitGameSession', a, {
    session: { id: `del-${Date.now()}-x`, gameId: 'speed_math', score: 600, correct: 10, wrong: 0, maxCombo: 10, maxLevel: 3, avgReactionMs: 900, bestReactionMs: 450, playedAt: Date.now() - 1000, durationSeconds: 60 },
  });
  await db.doc(`friends/${a.uid}/list/${b.uid}`).set({ uid: b.uid });
  await db.doc(`friends/${b.uid}/list/${a.uid}`).set({ uid: a.uid });
  await db.doc(`users/${b.uid}`).set({ stats: { friends: 1 } }, { merge: true });
  await db.doc(`pushTargets/${a.uid}`).set({ tokens: ['x'] });

  expect((await call('deleteAccount', a, {})).error?.status).toBe('INVALID_ARGUMENT');
  expect((await call('deleteAccount', a, { confirm: 'DELETE' })).result).toEqual({ deleted: true });

  expect((await db.doc(`users/${a.uid}`).get()).exists).toBe(false);
  expect((await db.doc(`usernames/${name}`).get()).exists).toBe(false);
  expect((await db.collection('gameSessions').where('uid', '==', a.uid).get()).empty).toBe(true);
  expect((await db.doc(`friends/${b.uid}/list/${a.uid}`).get()).exists).toBe(false);
  expect((await user(b.uid)).stats.friends).toBe(0);
  expect((await db.doc(`pushTargets/${a.uid}`).get()).exists).toBe(false);
  const weeks = await db.collection('leaderboards').get();
  for (const w of weeks.docs) expect((await w.ref.collection('entries').doc(a.uid).get()).exists).toBe(false);
  const lookup = await fetch(`${AUTH}/accounts:lookup?key=fake`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ idToken: a.token }) });
  expect(lookup.ok).toBe(false); // the sign-in account is gone
  void Timestamp;
});
