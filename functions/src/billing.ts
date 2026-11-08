import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { onMessagePublished } from 'firebase-functions/v2/pubsub';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { defineString } from 'firebase-functions/params';
import { logger } from 'firebase-functions/v2';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { checkProduct, checkSubscription, grantFor, PRODUCTS, tokenKey } from './billingRules';
import { economy } from './config';
import { db, REGION } from './db';
import { PlayApi, PlayApiError, RestPlayApi } from './playApi';

export const PACKAGE_NAME = defineString('ANDROID_PACKAGE_NAME', { default: 'com.neurorush.app' });
export const PLAY_API_BASE_URL = defineString('PLAY_API_BASE_URL', { default: 'https://androidpublisher.googleapis.com' });
/** Pub/Sub topic configured for Real-time developer notifications in Play Console. */
export const RTDN_TOPIC = 'play-billing';

let playApiOverride: PlayApi | null = null;
export function setPlayApi(api: PlayApi | null): void {
  playApiOverride = api;
}
function play(): PlayApi {
  return playApiOverride ?? new RestPlayApi(PACKAGE_NAME.value(), PLAY_API_BASE_URL.value());
}

function entitlementsResponse(user: FirebaseFirestore.DocumentData | undefined) {
  const e = user?.entitlements ?? {};
  return {
    removeAds: e.removeAds === true,
    pro: e.pro === true,
    proExpiresAt: e.proExpiresAt ? (e.proExpiresAt as Timestamp).toMillis() : null,
    themes: (e.themes as string[] | undefined) ?? [],
    coins: (user?.coins as number | undefined) ?? 0,
  };
}

/**
 * Verifies a Google Play purchase with the Play Developer API and grants it
 * exactly once (purchases/{sha256(token)}). Safe to call again for the same
 * purchase (e.g. after a crash or on "Restore purchases").
 */
export const verifyPurchase = onCall({ region: REGION }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  const productId = req.data?.productId;
  const token = req.data?.purchaseToken;
  const def = typeof productId === 'string' ? PRODUCTS[productId] : undefined;
  if (!def) throw new HttpsError('invalid-argument', 'Unknown product.');
  if (typeof token !== 'string' || token.length < 10 || token.length > 4096) throw new HttpsError('invalid-argument', 'Bad purchase token.');

  const api = play();
  let raw: Record<string, unknown>;
  try {
    raw = def.kind === 'subscription' ? await api.getSubscription(token) : await api.getProduct(def.id, token);
  } catch (e) {
    if (e instanceof PlayApiError && (e.status === 400 || e.status === 404 || e.status === 410)) {
      throw new HttpsError('not-found', 'Google Play does not recognise this purchase.');
    }
    logger.error('Play API failed', { error: (e as Error).message });
    throw new HttpsError('unavailable', 'Could not reach Google Play. Your purchase is safe — we will retry.');
  }
  const verdict = def.kind === 'subscription' ? checkSubscription(raw, uid) : checkProduct(raw, uid, def.kind);
  if (!verdict.ok) {
    if (verdict.reason === 'pending') throw new HttpsError('failed-precondition', 'Payment is still pending.');
    throw new HttpsError('permission-denied', `Purchase not valid (${verdict.reason}).`);
  }

  const key = tokenKey(token);
  const coinAmounts = await economy();
  const grant = grantFor(def, coinAmounts);
  const result = await db.runTransaction(async (tx) => {
    const pRef = db.doc(`purchases/${key}`);
    const uRef = db.doc(`users/${uid}`);
    const p = await tx.get(pRef);
    if (p.exists) {
      if (p.get('uid') !== uid) throw new HttpsError('permission-denied', 'This purchase belongs to another account.');
      if (def.kind === 'subscription' && verdict.expiresAt) {
        tx.set(uRef, { entitlements: { pro: true, proExpiresAt: Timestamp.fromMillis(verdict.expiresAt) } }, { merge: true });
      }
      return { status: 'already' as const, consumed: p.get('consumed') === true || verdict.consumed === true };
    }
    if (def.kind === 'consumable' && verdict.consumed) {
      throw new HttpsError('permission-denied', 'This purchase was already used.');
    }
    const updates: Record<string, unknown> = {};
    const ent: Record<string, unknown> = {};
    if (grant.removeAds) ent.removeAds = true;
    if (grant.themes) ent.themes = FieldValue.arrayUnion(...grant.themes);
    if (grant.pro) {
      ent.pro = true;
      ent.proExpiresAt = Timestamp.fromMillis(verdict.expiresAt!);
    }
    if (Object.keys(ent).length) updates.entitlements = ent;
    if (grant.coins) updates.coins = FieldValue.increment(grant.coins);
    tx.set(uRef, updates, { merge: true });
    tx.set(pRef, {
      uid,
      productId: def.id,
      kind: def.kind,
      orderId: verdict.orderId,
      purchaseToken: token,
      coins: grant.coins ?? null,
      expiresAt: verdict.expiresAt ? Timestamp.fromMillis(verdict.expiresAt) : null,
      consumed: false,
      createdAt: FieldValue.serverTimestamp(),
    });
    return { status: 'granted' as const, consumed: false };
  });

  // Acknowledge / consume after granting, so a failure never loses a paid item.
  try {
    if (def.kind === 'consumable' && !result.consumed) {
      await api.consumeProduct(def.id, token);
      await db.doc(`purchases/${key}`).update({ consumed: true });
    } else if (def.kind === 'consumable') {
      await db.doc(`purchases/${key}`).update({ consumed: true });
    } else if (verdict.needsAck) {
      if (def.kind === 'subscription') await api.acknowledgeSubscription(def.id, token);
      else await api.acknowledgeProduct(def.id, token);
    }
  } catch (e) {
    logger.error('Acknowledge/consume failed; the app will retry', { key, error: (e as Error).message });
  }
  const fresh = (await db.doc(`users/${uid}`).get()).data();
  return { status: result.status, ...entitlementsResponse(fresh) };
});

/** Applies the current Play state of a subscription purchase to its owner. */
async function refreshSubscription(token: string): Promise<void> {
  const pRef = db.doc(`purchases/${tokenKey(token)}`);
  const p = await pRef.get();
  if (!p.exists) return; // never verified by a user yet
  const uid = p.get('uid') as string;
  const raw = await play().getSubscription(token);
  const verdict = checkSubscription(raw, uid);
  const expiresAt = verdict.ok ? verdict.expiresAt! : Date.now();
  await db.doc(`users/${uid}`).set(
    { entitlements: { pro: verdict.ok, proExpiresAt: Timestamp.fromMillis(expiresAt) } },
    { merge: true },
  );
  await pRef.update({ expiresAt: Timestamp.fromMillis(expiresAt), state: raw.subscriptionState ?? null });
}

/** Real-time developer notifications: renewals, cancellations, refunds. */
export const playBillingNotifications = onMessagePublished({ topic: RTDN_TOPIC, region: REGION }, async (event) => {
  const msg = event.data.message.json as {
    subscriptionNotification?: { purchaseToken: string };
    voidedPurchaseNotification?: { purchaseToken: string; productType: number };
  };
  if (msg.subscriptionNotification) {
    await refreshSubscription(msg.subscriptionNotification.purchaseToken);
  } else if (msg.voidedPurchaseNotification) {
    await revoke(msg.voidedPurchaseNotification.purchaseToken);
  }
});

/** Refunded / charged-back purchase: remove what it granted. */
export async function revoke(token: string): Promise<void> {
  const pRef = db.doc(`purchases/${tokenKey(token)}`);
  await db.runTransaction(async (tx) => {
    const p = await tx.get(pRef);
    if (!p.exists || p.get('voided') === true) return;
    const uRef = db.doc(`users/${p.get('uid')}`);
    const u = await tx.get(uRef);
    const productId = p.get('productId') as string;
    const ent: Record<string, unknown> = {};
    if (productId === 'remove_ads') ent.removeAds = false;
    if (productId === 'neurorush_pro') ent.pro = false;
    if (productId === 'premium_themes') ent.themes = [];
    const updates: Record<string, unknown> = {};
    if (Object.keys(ent).length) updates.entitlements = ent;
    const coins = p.get('coins') as number | null;
    if (coins) updates.coins = Math.max(0, ((u.get('coins') as number) ?? 0) - coins);
    tx.set(uRef, updates, { merge: true });
    tx.update(pRef, { voided: true, voidedAt: FieldValue.serverTimestamp() });
  });
}

/** Daily safety net in case a notification was missed. */
export const recheckSubscriptions = onSchedule({ schedule: '30 3 * * *', timeZone: 'Etc/UTC', region: REGION }, async () => {
  const due = await db
    .collection('purchases')
    .where('kind', '==', 'subscription')
    .where('expiresAt', '<', Timestamp.fromMillis(Date.now() + 3600_000))
    .where('expiresAt', '>', Timestamp.fromMillis(Date.now() - 7 * 86400_000))
    .limit(500)
    .get();
  for (const d of due.docs) {
    await refreshSubscription(d.get('purchaseToken') as string).catch((e) => logger.warn('Recheck failed', { id: d.id, error: (e as Error).message }));
  }
});
