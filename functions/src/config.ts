import { getRemoteConfig } from 'firebase-admin/remote-config';
import { logger } from 'firebase-functions/v2';
import './db';

import { ECONOMY_DEFAULTS, Economy } from './economyRules';

export { ECONOMY_DEFAULTS };

let cache: { at: number; value: Economy } | null = null;

export async function economy(): Promise<Economy> {
  if (cache && Date.now() - cache.at < 5 * 60_000) return cache.value;
  let value: Economy = { ...ECONOMY_DEFAULTS };
  try {
    const template = await getRemoteConfig().getServerTemplate({ defaultConfig: ECONOMY_DEFAULTS });
    const cfg = template.evaluate();
    value = Object.fromEntries(
      Object.keys(ECONOMY_DEFAULTS).map((k) => [k, cfg.getNumber(k) || ECONOMY_DEFAULTS[k as keyof Economy]]),
    ) as Economy;
  } catch (e) {
    logger.debug('Remote Config server template unavailable, using defaults', { error: (e as Error).message });
  }
  cache = { at: Date.now(), value };
  return value;
}
