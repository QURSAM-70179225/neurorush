import { setGlobalOptions } from 'firebase-functions/v2';

setGlobalOptions({ maxInstances: 20 });

export { submitGameSession } from './sessions';
export { claimUsername } from './usernames';
export { sendFriendRequest, respondFriendRequest, removeFriend } from './friends';
export { weeklyLeaderboardReset } from './leaderboards';
export { getBrainCoachTip, getEndlessPuzzle, submitEndlessAnswer } from './aiFunctions';
