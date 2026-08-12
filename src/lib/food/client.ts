/**
 * Thin HTTP client for USDA FoodData Central.
 *
 * Reads FDC_API_KEY only — never EXPO_PUBLIC_*, which Expo inlines into the JS
 * bundle where the key is extractable from any install, and USDA deactivates
 * keys it finds published. So this runs only where a private key exists: the
 * harness today, a proxy later. PR 3 needs that proxy decision before the search
 * screen can call FDC.
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
  // Trimmed: `.env.example` ships `FDC_API_KEY=`, and an empty string is not
  // nullish, so it would sail past `??` and reach FDC as an unexplained 403.
  const key = process.env.FDC_API_KEY?.trim();
  if (key) return key;
  // Opt-in, never silent — a proxy missing its secret must fail rather than
  // quietly burn the shared demo quota. Only the local harness sets this.
  if (process.env.FDC_ALLOW_DEMO_KEY === '1') return 'DEMO_KEY';
  throw new FdcError(
    'FDC_API_KEY is missing or blank. Copy .env.example to .env and add a free key from https://fdc.nal.usda.gov/api-key-signup.html',
  );
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
    throw new FdcError(
      `Network request to FoodData Central failed for ${path}: ${cause}`,
    );
  }

  // Every throw below names `path`. /foods/search and /food/{id} otherwise
  // produce identical messages, and a failure from either is indistinguishable
  // in output — an ambiguity that sent two rounds of debugging at the wrong
  // call. It also separates "the quota was gone before we started" from "the
  // search worked and only some rows failed" during the N+1 fan-out.
  if (res.status === 429) {
    throw new FdcError(
      `FoodData Central rate limit reached for ${path}. DEMO_KEY allows 30 requests/hour — set FDC_API_KEY to a real key.`,
      429,
    );
  }
  if (!res.ok) {
    throw new FdcError(
      `FoodData Central returned ${res.status} ${res.statusText} for ${path}`,
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
      `FoodData Central returned an error for ${path}: ${body.error.message ?? body.error.code ?? 'unknown error'}`,
    );
  }

  return body;
}
