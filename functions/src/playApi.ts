import { GoogleAuth } from 'google-auth-library';

/** The parts of the Google Play Developer API used for purchases. */
export interface PlayApi {
  getProduct(productId: string, token: string): Promise<Record<string, unknown>>;
  acknowledgeProduct(productId: string, token: string): Promise<void>;
  consumeProduct(productId: string, token: string): Promise<void>;
  getSubscription(token: string): Promise<Record<string, unknown>>;
  acknowledgeSubscription(subscriptionId: string, token: string): Promise<void>;
}

export class PlayApiError extends Error {
  constructor(message: string, readonly status: number) {
    super(message);
  }
}

/**
 * REST client authenticated as the Functions service account (grant it
 * access in Play Console → Users and permissions). [baseUrl] can point to a
 * mock for emulator tests, in which case no Google credentials are used.
 */
export class RestPlayApi implements PlayApi {
  private auth = new GoogleAuth({ scopes: ['https://www.googleapis.com/auth/androidpublisher'] });

  constructor(private readonly packageName: string, private readonly baseUrl = 'https://androidpublisher.googleapis.com') {}

  private async request(path: string, method: 'GET' | 'POST' = 'GET'): Promise<Record<string, unknown>> {
    const url = `${this.baseUrl}/androidpublisher/v3/applications/${this.packageName}${path}`;
    const headers: Record<string, string> = { 'content-type': 'application/json' };
    if (this.baseUrl.startsWith('https://androidpublisher.googleapis.com')) {
      const client = await this.auth.getClient();
      const token = await client.getAccessToken();
      headers.authorization = `Bearer ${token.token}`;
    }
    const res = await fetch(url, { method, headers, body: method === 'POST' ? '{}' : undefined });
    const text = await res.text();
    if (!res.ok) throw new PlayApiError(`Play API ${res.status}: ${text.slice(0, 300)}`, res.status);
    return text ? (JSON.parse(text) as Record<string, unknown>) : {};
  }

  getProduct(productId: string, token: string) {
    return this.request(`/purchases/products/${encodeURIComponent(productId)}/tokens/${encodeURIComponent(token)}`);
  }
  async acknowledgeProduct(productId: string, token: string) {
    await this.request(`/purchases/products/${encodeURIComponent(productId)}/tokens/${encodeURIComponent(token)}:acknowledge`, 'POST');
  }
  async consumeProduct(productId: string, token: string) {
    await this.request(`/purchases/products/${encodeURIComponent(productId)}/tokens/${encodeURIComponent(token)}:consume`, 'POST');
  }
  getSubscription(token: string) {
    return this.request(`/purchases/subscriptionsv2/tokens/${encodeURIComponent(token)}`);
  }
  async acknowledgeSubscription(subscriptionId: string, token: string) {
    await this.request(`/purchases/subscriptions/${encodeURIComponent(subscriptionId)}/tokens/${encodeURIComponent(token)}:acknowledge`, 'POST');
  }
}
