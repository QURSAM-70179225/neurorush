import { BATTLE_QUESTIONS, generateBattle, seededRandom, STROOP_COLORS } from '../src/battleQuestions';
import { battleEndsAt, botPlan, currentQuestion, pointsFor, questionWindow, trophyResult } from '../src/battleRules';
import { localDay, overtakenGames, reminderFor } from '../src/notificationRules';

function evalMath(prompt: string): number {
  const [a, op, b] = prompt.split(' ');
  const x = Number(a), y = Number(b);
  return op === '+' ? x + y : op === '−' ? x - y : op === '×' ? x * y : x / y;
}

describe('battle questions', () => {
  test('same seed → same battle (both players see identical questions)', () => {
    expect(generateBattle(seededRandom(42))).toEqual(generateBattle(seededRandom(42)));
    expect(generateBattle(seededRandom(42))).not.toEqual(generateBattle(seededRandom(43)));
  });

  test('every question is well-formed and its answer is right', () => {
    for (let seed = 0; seed < 300; seed++) {
      const qs = generateBattle(seededRandom(seed));
      expect(qs).toHaveLength(BATTLE_QUESTIONS);
      for (const { question: q, answerIndex } of qs) {
        expect(q.choices).toHaveLength(4);
        expect(new Set(q.choices).size).toBe(4);
        expect(answerIndex).toBeGreaterThanOrEqual(0);
        if (q.type === 'math') {
          expect(Number(q.choices[answerIndex])).toBe(evalMath(q.prompt));
          expect(Number.isInteger(evalMath(q.prompt))).toBe(true);
        } else if (q.type === 'stroop') {
          expect(q.word).not.toBe(q.ink);
          expect(Number(q.choices[answerIndex])).toBe(q.ink);
          expect(q.choices.map(Number).every((c) => c >= 0 && c < STROOP_COLORS)).toBe(true);
          expect(q.choices).toContain(String(q.word));
        } else {
          const t = q.prompt.replace(', ?', '').split(', ').map(Number);
          const a = Number(q.choices[answerIndex]);
          const all = [...t, a];
          const d = all.slice(1).map((v, i) => v - all[i]);
          const d2 = d.slice(1).map((v, i) => v - d[i]);
          const ratio = all.slice(1).map((v, i) => v / all[i]);
          const fib = all.slice(2).every((v, i) => v === all[i] + all[i + 1]);
          const ok = new Set(d).size === 1 || new Set(d2).size === 1 || new Set(ratio).size === 1 || fib;
          expect(ok).toBe(true);
        }
        expect(q.choices.every((c) => Number(c) >= 0)).toBe(true);
      }
    }
  });
});

describe('battle rules', () => {
  test('timing windows', () => {
    expect(questionWindow(1000, 2, 8000)).toEqual({ opens: 17000, closes: 25000 });
    expect(battleEndsAt(1000, 8, 8000)).toBe(65000);
    expect(currentQuestion(1000, 8, 500)).toBe(-1);
    expect(currentQuestion(1000, 8, 9000)).toBe(1);
    expect(currentQuestion(1000, 8, 99999)).toBe(8);
  });

  test('points: 100 for correct + up to 100 for speed', () => {
    expect(pointsFor(false, 100)).toBe(0);
    expect(pointsFor(true, 0)).toBe(200);
    expect(pointsFor(true, 4000, 8000)).toBe(150);
    expect(pointsFor(true, 99999, 8000)).toBe(100);
  });

  test('trophies: win/lose/draw per mode, never below zero', () => {
    expect(trophyResult('random', { a: 900, b: 500 }, { a: 50, b: 100 })).toEqual({ winner: 'a', delta: { a: 30, b: -20 } });
    expect(trophyResult('random', { a: 100, b: 500 }, { a: 7, b: 0 })).toEqual({ winner: 'b', delta: { b: 30, a: -7 } });
    expect(trophyResult('invite', { a: 300, b: 300 }, {})).toEqual({ winner: null, delta: { a: 5, b: 5 } });
    expect(trophyResult('bot', { me: 100, 'neo-bot': 900 }, { me: 40 })).toEqual({ winner: 'neo-bot', delta: { 'neo-bot': 10, me: 0 } });
  });

  test('bot answers within the question time and gets most early questions right', () => {
    const plan = botPlan(seededRandom(7), 8, 8000);
    expect(plan.every((p) => p.ms > 0 && p.ms < 8000)).toBe(true);
    let correct = 0;
    for (let s = 0; s < 500; s++) correct += botPlan(seededRandom(s), 8).filter((p) => p.correct).length;
    expect(correct / 4000).toBeGreaterThan(0.5);
    expect(correct / 4000).toBeLessThan(0.75);
  });
});

describe('notifications', () => {
  const now = Date.UTC(2026, 10, 8, 14); // 19:00 in Pakistan (UTC+5)
  test('local days', () => {
    expect(localDay(now, 300)).toBe('2026-11-08');
    expect(localDay(Date.UTC(2026, 10, 8, 20), 300)).toBe('2026-11-09');
    expect(localDay(now, 300, -1)).toBe('2026-11-07');
  });
  test('streak reminder only when the streak is about to break', () => {
    expect(reminderFor('streak', { currentStreak: 5, streakDay: '2026-11-07' }, 300, now)?.title).toContain('5-day streak');
    expect(reminderFor('streak', { currentStreak: 5, streakDay: '2026-11-08' }, 300, now)).toBeNull(); // played today
    expect(reminderFor('streak', { currentStreak: 5, streakDay: '2026-11-05' }, 300, now)).toBeNull(); // already broken
    expect(reminderFor('streak', { currentStreak: 0, streakDay: '2026-11-07' }, 300, now)).toBeNull();
  });
  test('workout reminder unless already played today', () => {
    expect(reminderFor('workout', { streakDay: '2026-11-07' }, 300, now)).not.toBeNull();
    expect(reminderFor('workout', {}, 300, now)).not.toBeNull();
    expect(reminderFor('workout', { streakDay: '2026-11-08' }, 300, now)).toBeNull();
  });
  test('friend overtaken only when crossing their best', () => {
    expect(overtakenGames({ speed_math: 1000 }, { speed_math: 1600 }, { speed_math: 1500 })).toEqual(['speed_math']);
    expect(overtakenGames({ speed_math: 1550 }, { speed_math: 1600 }, { speed_math: 1500 })).toEqual([]); // already ahead
    expect(overtakenGames({}, { speed_math: 1400 }, { speed_math: 1500 })).toEqual([]); // still behind
    expect(overtakenGames({}, { color_clash: 900 }, { speed_math: 1500 })).toEqual([]); // friend never played it
  });
});
