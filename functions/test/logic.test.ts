import { ACHIEVEMENTS, isUnlocked, newlyUnlocked } from '../src/achievements';
import { GAMES } from '../src/catalog';
import { achievementStats, applySession, emptyProfile } from '../src/progress';
import { brainScore, levelFromXp, sessionRating, skillScore, starsFor, totalXpForLevel, xpFor } from '../src/rewards';
import { InvalidInput, parseSession, SessionInput, validateSession } from '../src/validation';
import { isoWeekId, weekStart } from '../src/weeks';

const NOW = Date.UTC(2026, 10, 8, 12);

function session(over: Partial<SessionInput> = {}): SessionInput {
  return {
    id: 'abcdef12-3456',
    gameId: 'speed_math',
    score: 1200,
    correct: 20,
    wrong: 3,
    maxCombo: 9,
    maxLevel: 6,
    avgReactionMs: 1400,
    bestReactionMs: 650,
    playedAt: NOW - 60_000,
    durationSeconds: 60,
    ...over,
  };
}

describe('rewards (mirror of the Dart rules)', () => {
  test('stars', () => {
    const g = GAMES.speed_math;
    expect(starsFor(g, 0, 0, 0)).toBe(0);
    expect(starsFor(g, 100, 0.5, 3)).toBe(1);
    expect(starsFor(g, 1800, 0.5, 10)).toBe(2);
    expect(starsFor(g, 3000, 0.79, 10)).toBe(2);
    expect(starsFor(g, 3000, 0.8, 10)).toBe(3);
  });
  test('xp', () => {
    expect(xpFor(0, 0, 0)).toBe(5);
    expect(xpFor(2000, 3, 0.95)).toBe(165);
    expect(xpFor(2000, 3, 0.85)).toBe(145);
  });
  test('levels', () => {
    expect(totalXpForLevel(2)).toBe(100);
    expect(totalXpForLevel(3)).toBe(240);
    expect(totalXpForLevel(50)).toBe(51940);
    expect(levelFromXp(239)).toBe(2);
    expect(levelFromXp(240)).toBe(3);
    expect(levelFromXp(1e9)).toBe(50);
  });
  test('brain score', () => {
    expect(sessionRating('speed_math', 5000, 1, 10, 60)).toBe(1);
    expect(sessionRating('speed_math', 600, 0.8, 4, 24)).toBeCloseTo(sessionRating('speed_math', 1500, 0.8, 4, 60));
    expect(skillScore([])).toBe(0);
    expect(skillScore([1])).toBe(200);
    expect(skillScore([1, 0])).toBeGreaterThan(skillScore([0, 1]));
    expect(brainScore({ speed: [1], memory: [0.5] }).total).toBe(300);
  });
});

describe('validation (anti-cheat)', () => {
  test('a normal round passes', () => expect(validateSession(session(), NOW)).toEqual({ ok: true }));

  test.each<[string, Partial<SessionInput>]>([
    ['duration', { durationSeconds: 45 }],
    ['future', { playedAt: NOW + 10 * 60_000 }],
    ['too_old', { playedAt: NOW - 30 * 86400_000 }],
    ['too_many_answers', { correct: 300, wrong: 0, maxCombo: 10, score: 300 * 60 }],
    ['combo', { maxCombo: 21 }],
    ['score_without_answers', { correct: 0, wrong: 5, maxCombo: 0, score: 10 }],
    ['score_too_high', { score: 20 * 60 * 5 + 1 }],
    ['score_too_low', { score: 20 * 15 - 1 }],
    ['reaction_inhuman', { bestReactionMs: 80 }],
    ['average_inhuman', { avgReactionMs: 120, bestReactionMs: 110 }],
    ['reaction_inconsistent', { avgReactionMs: 500, bestReactionMs: 600 }],
    ['reaction_inconsistent', { avgReactionMs: 500, bestReactionMs: null }],
  ])('rejects %s', (reason, over) => {
    expect(validateSession(session(over), NOW)).toEqual({ ok: false, reason });
  });

  test('Brain Test rounds (24 s) are allowed; maximum legitimate score passes', () => {
    expect(validateSession(session({ durationSeconds: 24, correct: 10, wrong: 0, maxCombo: 10, score: 900 }), NOW).ok).toBe(true);
    expect(validateSession(session({ score: 20 * 60 * 5 }), NOW).ok).toBe(true);
  });

  test('parseSession rejects malformed payloads', () => {
    expect(() => parseSession(null)).toThrow(InvalidInput);
    expect(() => parseSession({ ...session(), gameId: 'chess' })).toThrow('unknown game');
    expect(() => parseSession({ ...session(), id: 'x' })).toThrow('bad id');
    expect(() => parseSession({ ...session(), score: -1 })).toThrow(InvalidInput);
    expect(() => parseSession({ ...session(), score: 1.5 })).toThrow(InvalidInput);
    expect(() => parseSession({ ...session(), maxLevel: 11 })).toThrow(InvalidInput);
    expect(parseSession({ ...session(), avgReactionMs: undefined, bestReactionMs: undefined }).avgReactionMs).toBeNull();
  });

  test('every game has consistent bounds', () => {
    for (const g of Object.values(GAMES)) {
      expect(g.minBasePoints).toBeLessThan(g.maxBasePoints);
      expect(g.starThresholds[0]).toBeLessThan(g.starThresholds[1]);
      expect(g.starThresholds[1]).toBeLessThan(g.starThresholds[2]);
    }
    expect(Object.keys(GAMES)).toHaveLength(8);
  });
});

describe('applySession', () => {
  test('updates xp, level, bests, stats and brain score', () => {
    const { stars, xp, profile } = applySession(
      emptyProfile(),
      session({ score: 3000, correct: 20, wrong: 0, maxCombo: 20, maxLevel: 10, bestReactionMs: 280, avgReactionMs: 700 }),
    );
    expect(stars).toBe(3);
    expect(xp).toBe(150 + 45 + 20);
    expect(profile.xp).toBe(xp);
    expect(profile.level).toBe(levelFromXp(xp));
    expect(profile.rounds).toBe(1);
    expect(profile.bestScores.speed_math).toBe(3000);
    expect(profile.stats.threeStarRounds).toBe(1);
    expect(profile.stats.perfectRounds).toBe(1);
    expect(profile.stats.fastestReactionMs).toBe(280);
    expect(profile.stats.maxDifficulty).toBe(10);
    expect(profile.skills.speed).toBe(200);
    expect(profile.brainScore).toBe(200);
  });

  test('short rounds do not set best scores; profile input is not mutated', () => {
    const before = emptyProfile();
    const { profile } = applySession(before, session({ durationSeconds: 24, score: 900, correct: 10, wrong: 0, maxCombo: 10 }));
    expect(profile.bestScores.speed_math).toBeUndefined();
    expect(before.rounds).toBe(0);
  });

  test('skill ratings keep the 12 most recent', () => {
    let p = emptyProfile();
    for (let i = 0; i < 20; i++) p = applySession(p, session({ id: `session-${i}x` })).profile;
    expect(p.skillRatings.speed).toHaveLength(12);
  });
});

describe('achievements', () => {
  test('catalogue has 30 unique, well-formed badges', () => {
    expect(ACHIEVEMENTS).toHaveLength(30);
    expect(new Set(ACHIEVEMENTS.map((a) => a.id)).size).toBe(30);
    for (const a of ACHIEVEMENTS) expect(['>=', '<']).toContain(a.op);
  });

  test('Lightning Reflexes needs < 300 ms', () => {
    const a = ACHIEVEMENTS.find((x) => x.id === 'reflex_300')!;
    expect(isUnlocked(a, { fastestReactionMs: 299 })).toBe(true);
    expect(isUnlocked(a, { fastestReactionMs: 300 })).toBe(false);
    expect(isUnlocked(a, { fastestReactionMs: null })).toBe(false);
  });

  test('first round unlocks First Steps once', () => {
    const { profile } = applySession(emptyProfile(), session());
    const stats = achievementStats(profile, 1);
    expect(newlyUnlocked(stats, [])).toContain('first_round');
    expect(newlyUnlocked(stats, ['first_round'])).not.toContain('first_round');
  });
});

describe('weeks', () => {
  test('ISO week ids, including year boundaries', () => {
    expect(isoWeekId(new Date(Date.UTC(2026, 10, 8)))).toBe('2026-W45'); // Sunday
    expect(isoWeekId(new Date(Date.UTC(2026, 10, 9)))).toBe('2026-W46'); // Monday
    expect(isoWeekId(new Date(Date.UTC(2021, 0, 3)))).toBe('2020-W53');
    expect(isoWeekId(new Date(Date.UTC(2024, 11, 30)))).toBe('2025-W01');
  });
  test('week starts on Monday 00:00 UTC', () => {
    expect(weekStart(new Date(Date.UTC(2026, 10, 8, 23))).toISOString()).toBe('2026-11-02T00:00:00.000Z');
  });
});
