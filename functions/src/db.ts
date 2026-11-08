import { initializeApp, getApps } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

if (getApps().length === 0) initializeApp();
export const db = getFirestore();
export const REGION = 'asia-south1';

export const paths = {
  user: (uid: string) => `users/${uid}`,
  username: (name: string) => `usernames/${name}`,
  session: (id: string) => `gameSessions/${id}`,
  week: (weekId: string) => `leaderboards/${weekId}`,
  entry: (weekId: string, uid: string) => `leaderboards/${weekId}/entries/${uid}`,
  achievements: (uid: string) => `achievements/${uid}`,
  friend: (uid: string, friendUid: string) => `friends/${uid}/list/${friendUid}`,
  request: (toUid: string, fromUid: string) => `friends/${toUid}/requests/${fromUid}`,
};
