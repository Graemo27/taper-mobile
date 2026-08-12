/**
 * Thin HTTP client for USDA FoodData Central.
 *
 * Reads FDC_API_KEY only — never an EXPO_PUBLIC_* variable, which Expo inlines
 * into the JS bundle where the key is extractable from any install. USDA
 * deactivates keys it finds published. So this runs only where a private env var
 * exists: the harness today, a proxy later. The search screen (PR 3) needs that
 * proxy decision made first — it cannot call FDC directly.
 *
 * Falls back to DEMO_KEY (30 requests/hour). Free key:
 * https://fdc.nal.usda.gov/api-key-signup.html
 */

const BASE = 'https://api.nal.usda.gov/fdc/v1';

export class FdcError extends Error {
  status: number | undefined;

  constructor(message: string, status?: number) {
    super(message);
    this.name = 'FdcError';
    this.status = status;
  }
}

function apiKey(): string {
  return process.env.FDC_API_KEY ?? 'DEMO_KEY';
}

export async function fdcFetch<T>(
  path: string,
  params: Record<string, string | number>,
  signal?: AbortSignal,
): Promise<T> {
  const url = new URL(`${BASE}${path}`);
  url.searchParams.set('api_key', apiKey());
  for (const [k, v] of Object.entries(params)) {
    url.searchParams.set(k, String(v));
  }

  let res: Response;
  try {
    res = await fetch(url, { signal });
  } catch (cause) {
    if (cause instanceof Error && cause.name === 'AbortError') throw cause;
    throw new FdcError(`Network request to FoodData Central failed: ${cause}`);
  }

  if (res.status === 429) {
    throw new FdcError(
      'FoodData Central rate limit reached. DEMO_KEY allows 30 requests/hour — set FDC_API_KEY to a real key.',
      429,
    );
  }
  if (!res.ok) {
    throw new FdcError(
      `FoodData Central returned ${res.status} ${res.statusText}`,
      res.status,
    );
  }

  const body = (await res.json()) as T & {
    error?: { code?: string; message?: string };
  };

  // FDC has been observed returning an `error` envelope; without this an error
  // body would deserialise to `{ foods: undefined }` and read as "no results".
  if (body && typeof body === 'object' && body.error) {
    throw new FdcError(
      `FoodData Central: ${body.error.message ?? body.error.code ?? 'unknown error'}`,
    );
  }

  return body;
}
