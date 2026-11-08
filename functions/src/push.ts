import { defineBoolean } from 'firebase-functions/params';
import { logger } from 'firebase-functions/v2';
import { FieldValue } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { db } from './db';

/** In emulator tests pushes are written to pushLog instead of FCM. */
export const PUSH_DRY_RUN = defineBoolean('PUSH_DRY_RUN', { default: false });

export type PushKind = 'streak' | 'workout' | 'friends' | 'battle';

export interface PushMessage {
  title: string;
  body: string;
  /** Routing info for the app, e.g. {type: 'battle_invite', code: 'ABC234'}. */
  data: Record<string, string>;
}

/**
 * Sends to all devices of [uid] if they enabled [kind]. Tokens FCM reports
 * as dead are removed. Returns the number of devices reached.
 */
export async function sendPush(uid: string, kind: PushKind, msg: PushMessage): Promise<number> {
  const ref = db.doc(`pushTargets/${uid}`);
  const snap = await ref.get();
  const tokens = (snap.get('tokens') as string[] | undefined) ?? [];
  const enabled = snap.get(`prefs.${kind}`) !== false;
  if (!enabled || tokens.length === 0) return 0;

  if (PUSH_DRY_RUN.value()) {
    await db.collection('pushLog').add({ uid, kind, ...msg, devices: tokens.length, at: FieldValue.serverTimestamp() });
    return tokens.length;
  }
  // Devices register Firebase Installation IDs (FIDs), the current FCM target.
  const res = await getMessaging().sendEachForMulticast({
    fids: tokens,
    notification: { title: msg.title, body: msg.body },
    data: { ...msg.data, kind },
    android: { priority: 'high' },
  });
  const dead = res.responses
    .map((r, i) => (!r.success && ['messaging/installation-id-not-registered', 'messaging/registration-token-not-registered', 'messaging/invalid-argument'].includes(r.error?.code ?? '') ? tokens[i] : null))
    .filter((t): t is string => t !== null);
  if (dead.length) await ref.update({ tokens: FieldValue.arrayRemove(...dead) });
  if (res.failureCount > dead.length) logger.warn('Push failures', { uid, failures: res.failureCount });
  return res.successCount;
}
