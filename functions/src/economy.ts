import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { FieldValue } from 'firebase-admin/firestore';
import { economy } from './config';
import { db, REGION } from './db';
import { MAX_FREEZES, PREMIUM_THEMES } from './economyRules';

/** Buys an item with coins. Prices come from Remote Config (server template). */
export const spendCoins = onCall({ region: REGION }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  const item = req.data?.item;
  const prices = await economy();
  let price: number;
  let theme: string | null = null;
  if (item === 'streak_freeze') {
    price = prices.freeze_price_coins;
  } else if (typeof item === 'string' && item.startsWith('theme:') && PREMIUM_THEMES.includes(item.slice(6))) {
    price = prices.theme_price_coins;
    theme = item.slice(6);
  } else {
    throw new HttpsError('invalid-argument', 'Unknown item.');
  }
  return db.runTransaction(async (tx) => {
    const ref = db.doc(`users/${uid}`);
    const u = await tx.get(ref);
    const coins = (u.get('coins') as number | undefined) ?? 0;
    if (theme && ((u.get('entitlements.themes') as string[] | undefined) ?? []).includes(theme)) {
      throw new HttpsError('already-exists', 'You already own this theme.');
    }
    const freezes = (u.get('freezes') as number | undefined) ?? 0;
    if (!theme && freezes >= MAX_FREEZES) throw new HttpsError('failed-precondition', `You can hold up to ${MAX_FREEZES} streak freezes.`);
    if (coins < price) throw new HttpsError('failed-precondition', `You need ${price - coins} more coins.`);
    tx.set(
      ref,
      theme
        ? { coins: coins - price, entitlements: { themes: FieldValue.arrayUnion(theme) } }
        : { coins: coins - price, freezes: freezes + 1 },
      { merge: true },
    );
    return { coins: coins - price, freezes: theme ? freezes : freezes + 1, item };
  });
});
