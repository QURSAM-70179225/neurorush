import { coachMessages, fallbackCoachTip, generateCoachTip, weakestSkill } from '../src/ai/coach';
import { ChatMessage, cleanText, GroqClient, LlmClient, LlmError, requestBody } from '../src/ai/llm';
import {
  difficultyForRun, generatedSequencePuzzle, generateVerifiedPuzzle, parsePuzzle, puzzleHash, sequenceIsConsistent,
} from '../src/ai/puzzles';
import { createServer, Server } from 'http';
import { AddressInfo } from 'net';

class ScriptedLlm implements LlmClient {
  calls: ChatMessage[][] = [];
  constructor(private readonly replies: Record<string, unknown>[]) {}
  async json(messages: ChatMessage[]) {
    this.calls.push(messages);
    const r = this.replies.shift();
    if (!r) throw new LlmError('no more replies');
    return r;
  }
}

const skills = { memory: 120, focus: 90, speed: 150, logic: 60, language: 100 };
const input = {
  sessions: [{ gameId: 'speed_math', score: 1500, accuracy: 0.85, maxLevel: 6, avgReactionMs: 1300, stars: 2 }],
  skills,
  streak: 4,
};
const seq = { question: 'What comes next? 3, 6, 9, 12, 15, ?', choices: ['17', '18', '21', '16'], answerIndex: 1, explanation: 'Add 3 each time.' };

describe('coach', () => {
  test('reasoning models get low effort and room for hidden reasoning', () => {
    expect(requestBody('openai/gpt-oss-120b', [], { maxTokens: 300 })).toMatchObject({ max_tokens: 2000, reasoning_effort: 'low', reasoning_format: 'hidden' });
    expect(requestBody('llama-x', [], { maxTokens: 300 })).not.toHaveProperty('reasoning_effort');
    expect(requestBody('llama-x', [], { maxTokens: 300 }).max_tokens).toBe(300);
  });

  test('prompt contains only stats, the weakest skill and fixed names', () => {
    const m = coachMessages(input);
    expect(m[1].content).toContain('Games that train it: Number Sequence.');
    expect(m[1].content).toContain('Speed Math (speed skill): score 1500, accuracy 85%');
    expect(m[1].content).toContain('Weakest skill: logic');
    expect(weakestSkill(skills)).toBe('logic');
  });
  test('parses and cleans the model reply', async () => {
    const llm = new ScriptedLlm([{ tip: '  Try **Number Sequence** next!\n', funFact: 'Your brain has ~86 billion neurons.' }]);
    const t = await generateCoachTip(llm, input);
    expect(t).toEqual({ tip: 'Try Number Sequence next!', funFact: 'Your brain has ~86 billion neurons.', focusSkill: 'logic', source: 'ai' });
  });
  test('rejects replies with missing fields', async () => {
    await expect(generateCoachTip(new ScriptedLlm([{ tip: 'ok tip here' }]), input)).rejects.toThrow();
  });
  test('fallback targets the weakest skill', () => {
    const t = fallbackCoachTip(input, 3);
    expect(t.source).toBe('fallback');
    expect(t.focusSkill).toBe('logic');
    expect(t.tip.length).toBeGreaterThan(20);
  });
  test('cleanText caps length and strips control characters', () => {
    expect(cleanText('a\u0000b  c', 10)).toBe('a b c');
    expect(cleanText('x'.repeat(50), 10)).toHaveLength(10);
    expect(cleanText(42, 10)).toBeNull();
  });
});

describe('puzzles', () => {
  test('difficulty rises with the run', () => {
    expect(difficultyForRun(0)).toBe(1);
    expect(difficultyForRun(3)).toBe(2);
    expect(difficultyForRun(100)).toBe(5);
  });

  test('parsePuzzle validates structure', () => {
    expect(parsePuzzle(seq, 'sequence', 1)).toMatchObject({ answerIndex: 1, choices: ['17', '18', '21', '16'] });
    expect(parsePuzzle({ ...seq, choices: ['1', '1', '2', '3'] }, 'sequence', 1)).toBeNull();
    expect(parsePuzzle({ ...seq, choices: ['1', '2', '3'] }, 'sequence', 1)).toBeNull();
    expect(parsePuzzle({ ...seq, answerIndex: 4 }, 'sequence', 1)).toBeNull();
    expect(parsePuzzle({ ...seq, answerIndex: '1' }, 'sequence', 1)).toBeNull();
    expect(parsePuzzle({ ...seq, question: '' }, 'sequence', 1)).toBeNull();
    expect(parsePuzzle({ ...seq, choices: [17, 18, 21, 16] }, 'sequence', 1)?.choices).toEqual(['17', '18', '21', '16']);
  });

  test('sequence consistency check', () => {
    const p = (q: string, choices: string[], i: number) => parsePuzzle({ question: q, choices, answerIndex: i, explanation: 'because' }, 'sequence', 1)!;
    expect(sequenceIsConsistent(p('Next? 3, 6, 9, 12, 15', ['18', '17', '16', '20'], 0))).toBe(true);
    expect(sequenceIsConsistent(p('Next? 2, 4, 8, 16, 32', ['64', '48', '34', '62'], 0))).toBe(true);
    expect(sequenceIsConsistent(p('Next? 1, 4, 9, 16, 25', ['36', '30', '35', '49'], 0))).toBe(true);
    expect(sequenceIsConsistent(p('Next? 1, 1, 2, 3, 5, 8', ['13', '11', '12', '10'], 0))).toBe(true);
    expect(sequenceIsConsistent(p('Next? 1, 3, 4, 6, 7', ['9', '8', '10', '11'], 0))).toBe(true);
    // Wrong answer for the rule → rejected.
    expect(sequenceIsConsistent(p('Next? 3, 6, 9, 12, 15', ['18', '19', '16', '20'], 1))).toBe(false);
  });

  test('a puzzle is only accepted when an independent solve agrees', async () => {
    const llm = new ScriptedLlm([
      { ...seq, answerIndex: 1 }, { answerIndex: 2, confident: true }, // solver disagrees
      seq, { answerIndex: 1, confident: false }, // solver unsure
      seq, { answerIndex: 1, confident: true }, // agreed
    ]);
    const p = await generateVerifiedPuzzle(llm, 0, () => 0, new Set());
    expect(p?.answerIndex).toBe(1);
    expect(llm.calls).toHaveLength(6);
    // The solver never sees the answer or the explanation.
    const solverPrompt = JSON.stringify(llm.calls[1]);
    expect(solverPrompt).not.toContain('Add 3 each time');
    expect(solverPrompt).not.toContain('answerIndex": 1');
  });

  test('gives up after 3 bad attempts and skips repeats', async () => {
    const llm = new ScriptedLlm([seq, seq, seq]);
    const p = await generateVerifiedPuzzle(llm, 0, () => 0, new Set([puzzleHash(seq.question)]));
    expect(p).toBeNull();
    expect(llm.calls).toHaveLength(3);
  });

  test('generated fallback puzzles are correct and well-formed', () => {
    let seed = 1;
    const rnd = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
    for (let run = 0; run < 200; run++) {
      const p = generatedSequencePuzzle(run % 20, rnd);
      expect(p.choices).toHaveLength(4);
      expect(new Set(p.choices).size).toBe(4);
      expect(p.answerIndex).toBeGreaterThanOrEqual(0);
      expect(sequenceIsConsistent(p)).toBe(true);
      expect(p.choices.every((c) => Number(c) >= 0)).toBe(true);
    }
  });
});

describe('GroqClient', () => {
  let server: Server;
  let replies: { status: number; body: unknown }[] = [];
  let requests: { auth?: string; body: Record<string, unknown> }[] = [];
  let url = '';
  beforeAll(async () => {
    server = createServer((req, res) => {
      let data = '';
      req.on('data', (c) => (data += c));
      req.on('end', () => {
        requests.push({ auth: req.headers.authorization, body: JSON.parse(data) });
        const r = replies.shift() ?? { status: 500, body: {} };
        res.writeHead(r.status, { 'content-type': 'application/json' });
        res.end(JSON.stringify(r.body));
      });
    });
    await new Promise<void>((r) => server.listen(0, '127.0.0.1', () => r()));
    url = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  });
  afterAll(() => new Promise((r) => server.close(r)));
  beforeEach(() => {
    replies = [];
    requests = [];
  });
  const ok = (content: unknown) => ({ status: 200, body: { choices: [{ message: { content: JSON.stringify(content) } }] } });

  test('sends JSON mode with the key and model', async () => {
    replies.push(ok({ a: 1 }));
    const out = await new GroqClient('k', 'llama-x', url).json([{ role: 'user', content: 'hi' }]);
    expect(out).toEqual({ a: 1 });
    expect(requests[0].auth).toBe('Bearer k');
    expect(requests[0].body).toMatchObject({ model: 'llama-x', response_format: { type: 'json_object' } });
  });
  test('retries once on 429/5xx or bad JSON', async () => {
    replies.push({ status: 429, body: {} }, ok({ b: 2 }));
    expect(await new GroqClient('k', 'm', url).json([])).toEqual({ b: 2 });
    replies.push({ status: 200, body: { choices: [{ message: { content: 'not json' } }] } }, ok({ c: 3 }));
    expect(await new GroqClient('k', 'm', url).json([])).toEqual({ c: 3 });
  });
  test('retries once when Groq reports invalid JSON', async () => {
    replies.push({ status: 400, body: { error: { code: 'json_validate_failed' } } }, ok({ d: 4 }));
    expect(await new GroqClient('k', 'm', url).json([])).toEqual({ d: 4 });
  });
  test('fails fast on 401 and after two server errors', async () => {
    replies.push({ status: 401, body: { error: 'bad key' } });
    await expect(new GroqClient('k', 'm', url).json([])).rejects.toThrow('401');
    replies.push({ status: 503, body: {} }, { status: 503, body: {} });
    await expect(new GroqClient('k', 'm', url).json([])).rejects.toThrow('503');
  });
});
