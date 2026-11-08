import { setGlobalOptions } from 'firebase-functions/v2';

// App Check (Play Integrity): set ENFORCE_APP_CHECK=true in functions/.env.<project>
// after registering the app in Firebase Console → App Check (see SETUP.md).
setGlobalOptions({ maxInstances: 20, enforceAppCheck: process.env.ENFORCE_APP_CHECK === 'true' });

export { submitGameSession } from './sessions';
export { claimUsername } from './usernames';
export { sendFriendRequest, respondFriendRequest, removeFriend } from './friends';
export { weeklyLeaderboardReset } from './leaderboards';
export { getBrainCoachTip, getEndlessPuzzle, submitEndlessAnswer } from './aiFunctions';
export {
  findMatch, cancelMatch, startBotBattle, createInvite, challengeFriend, joinInvite,
  submitBattleAnswer, tickBattle, finishBattle, cleanupBattles,
} from './battles';
export { hourlyReminders, notifyFriendsOnNewBest } from './notifications';
export { verifyPurchase, playBillingNotifications, recheckSubscriptions } from './billing';
export { spendCoins } from './economy';
export { admobSsv, claimAdReward } from './ads';
export { deleteAccount } from './account';
