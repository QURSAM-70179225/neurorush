import { createHash } from 'crypto';
import { HttpsError, onCall, onRequest } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { economy } from './config';
import { db, REGION } from './db';
import { MAX_FREEZES, parseRewardCustomData } from './economyRules';
import { levelFromXp } from './rewards';
import { isoWeekId } from './weeks';

import { defineString } from 'firebase-functions/params';
import { setKeysUrl, verifySsv } from './ssv';

/** AdMob's public keys for SSV signatures (overridden only in emulator tests). */
export const ADMOB_KEYS_URL = defineString('ADMOB_KEYS_URL', { default: 'https://www.gstatic.com/admob/reward/verifier-keys.json' });
/** AdMob calls this after a rewarded ad is watched (configure the URL in AdMob). */
export const admobSsv = onRequest({ region: REGION }, async (req, res) => {
  setKeysUrl(ADMOB_KEYS_URL.value());
  const raw = req.originalUrl.split('?')[1] ?? '';
  const params = await verifySsv(raw).catch(() => null);
  if (!params) {
    logger.warn('Rejected SSV callback');
    res.status(400).send('invalid signature');
    return;
  }
  const ts = Number(params.get('timestamp'));
  const uid = params.get('user_id') ?? '';
  const data = parseRewardCustomData(params.get('custom_data') ?? '');
  const txId = params.get('transaction_id') ?? '';
  if (!data || !uid || !txId || !Number.isFinite(ts) || Math.abs(Date.now() - ts) > 3600_000) {
    res.status(400).send('bad payload');
    return;
  }
  const id = createHash('sha256').update(txId).digest('hex');
  await db.doc(`rewardGrants/${id}`).create({
    uid, reward: data.reward, nonce: data.nonce, sessionId: data.sessionId, claimed: false, verifiedAt: FieldValue.serverTimestamp(),
  }).catch(() => undefined); // AdMob may retry: the first write wins
  res.status(200).send('ok');
});

/**
 * The app calls this after the ad closes. Applies the reward only if AdMob
 * verified it (rewardGrants), once, within the daily limit.
 */
export const claimAdReward = onCall({ region: REGION }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  const nonce = req.data?.nonce;
  if (typeof nonce !== 'string' || !/^[A-Za-z0-9-]{8,64}$/.test(nonce)) throw new HttpsError('invalid-argument', 'bad nonce');
  const grants = await db.collection('rewardGrants').where('uid', '==', uid).where('nonce', '==', nonce).limit(1).get();
  if (grants.empty) throw new HttpsError('not-found', 'Reward not verified yet.');
  const limit = (await economy()).rewarded_daily_limit;
  const today = new Date().toISOString().slice(0, 10);

  return db.runTransaction(async (tx) => {
    const gRef = grants.docs[0].ref;
    const g = await tx.get(gRef);
    const uRef = db.doc(`users/${uid}`);
    const u = await tx.get(uRef);
    const reward = g.get('reward') as string;
    if (g.get('claimed') === true) return { reward, applied: false, reason: 'already_claimed' };
    const counts = (u.get('adRewards') as { day?: string; count?: number } | undefined) ?? {};
    const used = counts.day === today ? counts.count ?? 0 : 0;
    if (used >= limit) {
      tx.update(gRef, { claimed: true, result: 'daily_limit' });
      return { reward, applied: false, reason: 'daily_limit' };
    }
    const updates: Record<string, unknown> = { adRewards: { day: today, count: used + 1 } };
    let applied = true;
    let reason: string | undefined;

    if (reward === 'streak_freeze') {
      const freezes = (u.get('freezes') as number | undefined) ?? 0;
      if (freezes >= MAX_FREEZES) {
        applied = false;
        reason = 'max_freezes';
      } else {
        updates.freezes = freezes + 1;
      }
    } else if (reward === 'extra_life') {
      const e = (u.get('endless') as Record<string, unknown> | undefined) ?? {};
      if (e.lives === 0 && e.revived !== true) {
        updates.endless = { ...e, lives: 1, revived: true };
      } else {
        applied = false;
        reason = 'not_game_over';
      }
    } else if (reward === 'double_xp') {
      const sessionId = g.get('sessionId') as string | null;
      if (!sessionId) {
        applied = false;
        reason = 'no_session';
      } else {
        const sRef = db.doc(`gameSessions/${sessionId}`);
        const s = await tx.get(sRef);
        if (!s.exists) {
          // Round not uploaded yet: submitGameSession doubles it on arrival.
          updates.pendingBoosts = { [sessionId]: true };
        } else if (s.get('uid') !== uid || s.get('boosted') === true) {
          applied = false;
          reason = 'not_eligible';
        } else {
          const xp = s.get('xp') as number;
          const weekId = s.get('weekId') as string;
          const eRef = db.doc(`leaderboards/${weekId}/entries/${uid}`);
          const entry = await tx.get(eRef);
          const total = ((u.get('xp') as number | undefined) ?? 0) + xp;
          updates.xp = total;
          updates.level = levelFromXp(total);
          tx.update(sRef, { boosted: true, xp: xp * 2 });
          if (entry.exists && weekId === isoWeekId(new Date())) tx.update(eRef, { xp: FieldValue.increment(xp) });
        }
      }
    }
    tx.set(uRef, updates, { merge: true });
    tx.update(gRef, { claimed: true, result: applied ? 'applied' : reason, claimedAt: Timestamp.now() });
    return { reward, applied, reason };
  });
});
