import { ChatMessage, cleanText, LlmClient } from './llm';
import { GAMES, SKILLS, Skill } from '../catalog';

export interface DaySession {
  gameId: string;
  score: number;
  accuracy: number;
  maxLevel: number;
  avgReactionMs: number | null;
  stars: number;
}

export interface CoachInput {
  sessions: DaySession[];
  skills: Record<Skill, number>;
  streak: number;
}

export interface CoachTip {
  tip: string;
  funFact: string;
  focusSkill: Skill;
  source: 'ai' | 'fallback';
}

const GAME_NAMES: Record<string, string> = {
  memory_grid: 'Memory Grid',
  color_clash: 'Color Clash',
  speed_math: 'Speed Math',
  shape_match: 'Shape Match',
  number_sequence: 'Number Sequence',
  word_scramble: 'Word Scramble',
  odd_one_out: 'Odd One Out',
  path_recall: 'Path Recall',
};

export function weakestSkill(skills: Record<Skill, number>): Skill {
  return SKILLS.reduce((a, b) => (skills[b] < skills[a] ? b : a));
}

/**
 * Prompt built only from numbers and fixed game names — no user-provided
 * text reaches the model, so there is nothing to inject.
 */
export function coachMessages(input: CoachInput): ChatMessage[] {
  const lines = input.sessions.map((s) => {
    const g = GAMES[s.gameId];
    return `- ${GAME_NAMES[s.gameId] ?? s.gameId} (${g?.skill ?? 'unknown'} skill): score ${s.score}, ` +
      `accuracy ${Math.round(s.accuracy * 100)}%, reached difficulty ${s.maxLevel}/10, ` +
      `${s.avgReactionMs === null ? 'no reaction data' : `average reaction ${s.avgReactionMs} ms`}, ${s.stars}/3 stars`;
  });
  const skills = SKILLS.map((s) => `${s} ${input.skills[s]}/200`).join(', ');
  const weakest = weakestSkill(input.skills);
  const games = Object.values(GAMES)
    .filter((g) => g.skill === weakest)
    .map((g) => GAME_NAMES[g.id])
    .join(' or ');
  return [
    {
      role: 'system',
      content:
        'You are Neo, the upbeat brain coach of NeuroRush, a brain-training game. ' +
        'Reply ONLY with a JSON object: {"tip": string, "funFact": string}. ' +
        '"tip": 1–2 short sentences (max 220 characters) of specific, encouraging advice based on the stats, ' +
        'recommending exactly one of the games named in the message, by its exact name. Never invent game names. ' +
        'No medical claims, no diagnosis. ' +
        '"funFact": one surprising, well-established fact about the human brain (max 200 characters). ' +
        'Only state facts found in neuroscience textbooks; avoid exaggerations. ' +
        'Simple English suitable for teenagers and adults. No emojis, no markdown.',
    },
    {
      role: 'user',
      content:
        `Today's workout:\n${lines.join('\n')}\n` +
        `Skill scores: ${skills}. Weakest skill: ${weakest}. ` +
        `Games that train it: ${games}. ` +
        `Current daily streak: ${input.streak} days.`,
    },
  ];
}

export async function generateCoachTip(llm: LlmClient, input: CoachInput): Promise<CoachTip> {
  const out = await llm.json(coachMessages(input), { temperature: 0.8, maxTokens: 300 });
  const tip = cleanText(out.tip, 240);
  const funFact = cleanText(out.funFact, 220);
  if (!tip || !funFact) throw new Error('Coach reply missing fields');
  return { tip, funFact, focusSkill: weakestSkill(input.skills), source: 'ai' };
}

/** Hand-written advice used when the AI is unavailable. */
const FALLBACK_TIPS: Record<Skill, string[]> = {
  memory: [
    'Your memory is the skill with the most room to grow. Try a Memory Grid round and chunk the tiles into small shapes instead of single squares.',
    'Path Recall rewards saying the route in your head — "up, right, right" — as it plays. Give it a go tomorrow.',
  ],
  focus: [
    'Focus is your growth area. In Color Clash, blur your eyes slightly and react to the colour before you read the word.',
    'Odd One Out trains steady attention: scan the grid row by row instead of jumping around.',
  ],
  speed: [
    'Speed is where you can gain the most. In Speed Math, answer the easy ones instantly to build a big combo early.',
    'Shape Match gets faster with rhythm — keep a steady tempo instead of rushing and slipping.',
  ],
  logic: [
    'Logic is your next frontier. In Number Sequence, check the differences between numbers first, then the ratios.',
    'When a sequence looks random, look at every second number — two patterns may be taking turns.',
  ],
  language: [
    'Language has the most room to grow. In Word Scramble, find common endings like -ing or -er first.',
    'Try Word Scramble in both English and Urdu — switching languages is a great workout for your brain.',
  ],
};

const FALLBACK_FACTS = [
  'Your brain uses about 20% of your body’s energy while making up only around 2% of its weight.',
  'Sleep helps lock in memories: the brain replays what you learned during the day while you rest.',
  'The brain keeps forming new connections throughout life — this is called neuroplasticity.',
  'Signals in your nerves can travel at over 100 metres per second.',
  'Short breaks during practice help your brain consolidate skills faster than non-stop drilling.',
  'Physical exercise increases blood flow to the brain and is linked to better memory.',
];

export function fallbackCoachTip(input: CoachInput, seed: number): CoachTip {
  const focus = weakestSkill(input.skills);
  const tips = FALLBACK_TIPS[focus];
  return {
    tip: tips[seed % tips.length],
    funFact: FALLBACK_FACTS[seed % FALLBACK_FACTS.length],
    focusSkill: focus,
    source: 'fallback',
  };
}
