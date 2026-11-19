// Live check of the AI prompts against Groq (no Firebase needed).
// Usage: npm run build && GROQ_API_KEY=gsk_... [GROQ_MODEL=...] node scripts/groq-smoke.js
const { GroqClient } = require('../lib/ai/llm');
const { generateCoachTip } = require('../lib/ai/coach');
const { generateVerifiedPuzzle } = require('../lib/ai/puzzles');

(async () => {
  const key = process.env.GROQ_API_KEY;
  if (!key) throw new Error('Set GROQ_API_KEY');
  const llm = new GroqClient(key, process.env.GROQ_MODEL || 'openai/gpt-oss-120b');
  const tip = await generateCoachTip(llm, {
    sessions: [
      { gameId: 'speed_math', score: 1650, accuracy: 0.88, maxLevel: 6, avgReactionMs: 1250, stars: 2 },
      { gameId: 'word_scramble', score: 420, accuracy: 0.6, maxLevel: 3, avgReactionMs: 5200, stars: 1 },
    ],
    skills: { memory: 110, focus: 95, speed: 140, logic: 70, language: 85 },
    streak: 5,
  });
  console.log('COACH', tip);
  for (let run = 0; run < 9; run += 4) {
    const t0 = Date.now();
    const p = await generateVerifiedPuzzle(llm, run, Math.random, new Set());
    console.log(`PUZZLE run=${run} (${Date.now() - t0} ms)`, p ?? 'rejected by verification (server would use a generated puzzle)');
  }
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
