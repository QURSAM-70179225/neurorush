/** Minimal chat-completion client for Groq's OpenAI-compatible API. */
export interface ChatMessage {
  role: 'system' | 'user' | 'assistant';
  content: string;
}

export interface LlmClient {
  /** Returns the parsed JSON object produced by the model. */
  json(messages: ChatMessage[], opts?: { temperature?: number; maxTokens?: number }): Promise<Record<string, unknown>>;
}

export class LlmError extends Error {}

export class GroqClient implements LlmClient {
  constructor(
    private readonly apiKey: string,
    private readonly model: string,
    private readonly baseUrl = 'https://api.groq.com/openai/v1',
    private readonly timeoutMs = 12000,
  ) {}

  async json(messages: ChatMessage[], opts: { temperature?: number; maxTokens?: number } = {}): Promise<Record<string, unknown>> {
    let lastError: Error = new LlmError('No attempt made');
    // One retry for transient problems (network, 429, 5xx, malformed JSON).
    for (let attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) await new Promise((r) => setTimeout(r, 500));
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), this.timeoutMs);
      let res: Response;
      try {
        res = await fetch(`${this.baseUrl}/chat/completions`, {
          method: 'POST',
          signal: controller.signal,
          headers: { 'content-type': 'application/json', authorization: `Bearer ${this.apiKey}` },
          body: JSON.stringify({
            model: this.model,
            messages,
            temperature: opts.temperature ?? 0.7,
            max_tokens: opts.maxTokens ?? 400,
            response_format: { type: 'json_object' },
          }),
        });
      } catch (e) {
        lastError = new LlmError(`Network error: ${(e as Error).message}`);
        continue;
      } finally {
        clearTimeout(timer);
      }
      if (res.status === 429 || res.status >= 500) {
        lastError = new LlmError(`Groq HTTP ${res.status}`);
        continue;
      }
      if (!res.ok) throw new LlmError(`Groq HTTP ${res.status}: ${(await res.text()).slice(0, 200)}`);
      try {
        const body = (await res.json()) as { choices?: { message?: { content?: string } }[] };
        const parsed = JSON.parse(body.choices?.[0]?.message?.content ?? '') as unknown;
        if (typeof parsed === 'object' && parsed !== null && !Array.isArray(parsed)) return parsed as Record<string, unknown>;
        lastError = new LlmError('Completion is not a JSON object');
      } catch {
        lastError = new LlmError('Completion is not valid JSON');
      }
    }
    throw lastError;
  }
}

/** Collapses whitespace, strips control chars and markup, and caps length. */
export function cleanText(v: unknown, maxLen: number, minLen = 3): string | null {
  if (typeof v !== 'string') return null;
  const s = v
    .replace(/[\u0000-\u001f\u007f]/g, ' ')
    .replace(/[<>*_`#]/g, '')
    .replace(/\s+/g, ' ')
    .trim();
  if (s.length < minLen) return null;
  return s.length > maxLen ? `${s.slice(0, maxLen - 1).trimEnd()}…` : s;
}
