import { setGlobalOptions } from 'firebase-functions/v2';

setGlobalOptions({ maxInstances: 20 });

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
