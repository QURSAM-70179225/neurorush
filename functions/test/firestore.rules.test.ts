import { assertFails, assertSucceeds, initializeTestEnvironment, RulesTestEnvironment } from '@firebase/rules-unit-testing';
import { readFileSync } from 'fs';
import { doc, getDoc, setDoc, updateDoc, deleteDoc, Timestamp } from 'firebase/firestore';

let env: RulesTestEnvironment;

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-neurorush',
    firestore: { rules: readFileSync('../firestore.rules', 'utf8'), host: '127.0.0.1', port: 8080 },
  });
});
afterAll(() => env.cleanup());
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users/alice'), { username: 'alice', xp: 100, level: 2, displayName: 'Alice', currentStreak: 2, bestStreak: 5 });
    await setDoc(doc(db, 'gameSessions/s1'), { uid: 'alice', score: 100 });
    await setDoc(doc(db, 'leaderboards/2026-W45/entries/alice'), { uid: 'alice', xp: 100 });
    await setDoc(doc(db, 'friends/alice/requests/bob'), { fromUid: 'bob' });
    await setDoc(doc(db, 'achievements/alice'), { unlocked: { first_round: Timestamp.now() } });
  });
});

const alice = () => env.authenticatedContext('alice').firestore();
const bob = () => env.authenticatedContext('bob').firestore();
const anon = () => env.unauthenticatedContext().firestore();

describe('users', () => {
  test('signed-in players can read profiles; signed-out cannot', async () => {
    await assertSucceeds(getDoc(doc(bob(), 'users/alice')));
    await assertFails(getDoc(doc(anon(), 'users/alice')));
  });
  test('owner can edit cosmetic and streak fields', async () => {
    await assertSucceeds(updateDoc(doc(alice(), 'users/alice'), { displayName: 'Ali', country: 'PK', currentStreak: 3, bestStreak: 5 }));
  });
  test('owner cannot touch XP, level or username', async () => {
    await assertFails(updateDoc(doc(alice(), 'users/alice'), { xp: 999999 }));
    await assertFails(updateDoc(doc(alice(), 'users/alice'), { level: 50 }));
    await assertFails(updateDoc(doc(alice(), 'users/alice'), { username: 'king' }));
  });
  test('field validation', async () => {
    await assertFails(updateDoc(doc(alice(), 'users/alice'), { country: 'Pakistan' }));
    await assertFails(updateDoc(doc(alice(), 'users/alice'), { displayName: 'x'.repeat(31) }));
    await assertFails(updateDoc(doc(alice(), 'users/alice'), { currentStreak: 9, bestStreak: 5 }));
  });
  test('nobody can edit someone else', async () => {
    await assertFails(updateDoc(doc(bob(), 'users/alice'), { displayName: 'hacked' }));
  });
  test('private data is owner-only', async () => {
    await assertSucceeds(setDoc(doc(alice(), 'users/alice/private/progress'), { freezes: 1 }));
    await assertFails(getDoc(doc(bob(), 'users/alice/private/progress')));
  });
});

describe('competitive data is server-only', () => {
  test('sessions: owner reads, nobody writes', async () => {
    await assertSucceeds(getDoc(doc(alice(), 'gameSessions/s1')));
    await assertFails(getDoc(doc(bob(), 'gameSessions/s1')));
    await assertFails(setDoc(doc(alice(), 'gameSessions/s2'), { uid: 'alice', score: 1e9 }));
  });
  test('leaderboards: readable, not writable', async () => {
    await assertSucceeds(getDoc(doc(bob(), 'leaderboards/2026-W45/entries/alice')));
    await assertFails(setDoc(doc(alice(), 'leaderboards/2026-W45/entries/alice'), { xp: 1e9 }));
  });
  test('achievements: readable, not writable', async () => {
    await assertSucceeds(getDoc(doc(bob(), 'achievements/alice')));
    await assertFails(setDoc(doc(alice(), 'achievements/alice'), { unlocked: { level_50: 1 } }));
  });
  test('usernames cannot be claimed directly', async () => {
    await assertFails(setDoc(doc(alice(), 'usernames/admin'), { uid: 'alice' }));
  });
});

describe('friends', () => {
  test('owner reads and can decline requests; cannot forge friendships', async () => {
    await assertSucceeds(getDoc(doc(alice(), 'friends/alice/requests/bob')));
    await assertFails(getDoc(doc(bob(), 'friends/alice/requests/bob')));
    await assertSucceeds(deleteDoc(doc(alice(), 'friends/alice/requests/bob')));
    await assertFails(setDoc(doc(alice(), 'friends/alice/list/bob'), { uid: 'bob' }));
    await assertFails(setDoc(doc(bob(), 'friends/alice/requests/bob'), { fromUid: 'bob' }));
  });
});

describe('daily workouts', () => {
  test('owner writes well-formed days only', async () => {
    await assertSucceeds(setDoc(doc(alice(), 'dailyWorkouts/alice/days/2026-11-08'), { games: ['speed_math'], completed: [], updatedAt: Timestamp.now() }));
    await assertFails(setDoc(doc(alice(), 'dailyWorkouts/alice/days/today'), { games: [], completed: [] }));
    await assertFails(setDoc(doc(bob(), 'dailyWorkouts/alice/days/2026-11-08'), { games: [], completed: [] }));
  });
});
