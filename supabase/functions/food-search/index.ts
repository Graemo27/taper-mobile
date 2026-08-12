/**
 * Food search proxy.
 *
 * Exists because the FDC key cannot ship to the client. Expo inlines every
 * `EXPO_PUBLIC_*` var into the JS bundle, where it is extractable from any
 * install, and USDA deactivates keys it finds published. So the key lives here
 * as a Supabase secret and the app never sees it.
 *
 * The whole N+1 fan-out runs server-side. FDC has no batch endpoint that
 * includes portions, so a five-row result costs six requests; doing that from
 * the device would mean six round trips over mobile network instead of one, and
 * would leak the shape of the quota to anyone watching.
 *
 * The lookup logic is imported, not reimplemented — `src/lib/food` is the same
 * code the Node harness runs, so `npm run food` stays a faithful test of what
 * this serves.
 */

import { FdcError, searchWithServings } from '../../../src/lib/food/index.ts';

/** Expo also targets web, where a browser will preflight this. */
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

/**
 * Confirms the caller is a signed-in user rather than the app's public key.
 *
 * `verify_jwt = true` already proved the signature, so the payload is read
 * without re-verifying it — but a valid signature is not the same as a user.
 * The legacy anon key is itself a signed JWT and it ships inside the bundle,
 * so it clears platform verification while carrying `role: "anon"` and no
 * `sub`. Requiring an `authenticated` role with a subject is what actually
 * distinguishes a session from the key everyone has.
 *
 * Anonymous *users* pass deliberately: they hold `role: "authenticated"` with
 * `is_anonymous: true`, which is a real account the journal can hang off.
 */
function userId(req: Request): string | null {
  const token = req.headers.get('Authorization')?.replace(/^Bearer\s+/i, '');
  if (!token) return null;

  const payload = token.split('.')[1];
  if (!payload) return null;

  try {
    // base64url → base64; atob rejects the URL-safe alphabet and bare padding.
    const normalised = payload.replace(/-/g, '+').replace(/_/g, '/');
    const claims = JSON.parse(
      atob(normalised.padEnd(Math.ceil(normalised.length / 4) * 4, '=')),
    ) as { role?: string; sub?: string };

    if (claims.role !== 'authenticated' || !claims.sub) return null;
    return claims.sub;
  } catch {
    return null;
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'Use POST.' }, 405);

  if (!userId(req)) {
    return json({ error: 'Sign in required.' }, 401);
  }

  let body: { query?: unknown; limit?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'Body must be JSON.' }, 400);
  }

  const query = typeof body.query === 'string' ? body.query.trim() : '';
  if (query === '') return json({ error: 'A query is required.' }, 400);

  // Capped, not just validated. Each row costs an FDC request against a shared
  // quota, so an unbounded limit is a way to exhaust it from one device.
  const raw = body.limit === undefined ? 5 : Number(body.limit);
  if (!Number.isSafeInteger(raw) || raw < 1 || raw > 10) {
    return json({ error: 'limit must be an integer from 1 to 10.' }, 400);
  }

  // Correlates a user's report with a log line without the log holding what
  // they typed. Returned on every failure so "it broke" becomes answerable.
  const requestId = crypto.randomUUID();

  try {
    const { foods, unavailable } = await searchWithServings(query, raw);
    return json({ foods, unavailable });
  } catch (err) {
    if (err instanceof FdcError) {
      // 429 is forwarded so the app can say "try again shortly" rather than
      // "no such food". Everything else becomes 502: the failure is upstream,
      // and echoing FDC's status would imply this function was at fault.
      const status = err.status === 429 ? 429 : 502;
      console.error(`[${requestId}] FDC lookup failed, upstream ${err.status ?? 'none'}: ${err.message}`);
      return json(
        {
          // Not `err.message`. FdcError is written for whoever runs the server —
          // it names the FDC endpoint and tells the reader to set FDC_API_KEY.
          // That is operator advice, and it has no business inside a food app.
          error:
            status === 429
              ? 'Too many lookups right now. Try again shortly.'
              : 'Food lookup is unavailable right now.',
          requestId,
        },
        status,
      );
    }
    console.error(`[${requestId}] Unexpected failure:`, err);
    return json({ error: 'Lookup failed.', requestId }, 500);
  }
});
