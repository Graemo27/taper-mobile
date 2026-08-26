/**
 * Licensed-NRT product search.
 *
 * The app's only route to a product catalogue, and deliberately the only one.
 * Search, autocomplete and suggestions must never surface a tobacco product —
 * pouches, vapes, cigarettes — because the app should not help anyone shop for
 * nicotine it is not licensed to recommend. See the standing constraint in
 * `AGENTS.md`.
 *
 * That rule is enforced twice, in ways that fail closed. openFDA's drug
 * endpoint holds drugs, and pouches are regulated as tobacco products by a
 * different centre, so they are absent from the source rather than filtered out
 * of it. Then `nrt/types.ts` allowlists the five licensed delivery forms, so
 * anything nicotine-bearing that reaches this code without being a cessation
 * product is dropped. Note what this handler does *not* accept: there is no
 * product-type or category parameter, so no caller can widen the search.
 *
 * The entrypoint is one line so that importing it does not start a server, and
 * everything worth testing is reached by calling `handle` with a `Request`.
 */

import { OpenFdaError, searchNrt } from './nrt/openfda.ts';

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
 * `verify_jwt = true` proves the signature,
 * but the anon key is itself a signed JWT that ships in the bundle, so it
 * clears verification while carrying `role: "anon"` and no `sub`. Anonymous
 * *users* pass deliberately — they hold `role: "authenticated"` with
 * `is_anonymous: true`, and every user in this project is one.
 */
function isUser(req: Request): boolean {
  const token = req.headers.get('Authorization')?.replace(/^Bearer\s+/i, '');
  const payload = token?.split('.')[1];
  if (!payload) return false;

  try {
    // base64url → base64; atob rejects the URL-safe alphabet and bare padding.
    const normalised = payload.replace(/-/g, '+').replace(/_/g, '/');
    const claims = JSON.parse(
      atob(normalised.padEnd(Math.ceil(normalised.length / 4) * 4, '=')),
    ) as { role?: string; sub?: string };
    return claims.role === 'authenticated' && !!claims.sub;
  } catch {
    return false;
  }
}

/** The whole request path, as a plain function, so a test can call it directly. */
export async function handle(req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'Use POST.' }, 405);
  if (!isUser(req)) return json({ error: 'Sign in required.' }, 401);

  // `null`, `[]` and `42` are all valid JSON, so the parse succeeds and this
  // guard is what stops them reaching a property access and becoming a 500.
  let body: { query?: unknown; limit?: unknown };
  try {
    const parsed: unknown = await req.json();
    if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
      return json({ error: 'Body must be JSON.' }, 400);
    }
    body = parsed as { query?: unknown; limit?: unknown };
  } catch {
    return json({ error: 'Body must be JSON.' }, 400);
  }

  const query = typeof body.query === 'string' ? body.query.trim() : '';
  if (query === '') return json({ error: 'A query is required.' }, 400);

  const limit = body.limit === undefined ? 8 : Number(body.limit);
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > 25) {
    return json({ error: 'limit must be an integer from 1 to 25.' }, 400);
  }

  // Correlates a user's report with a log line without the log holding what
  // they typed. Returned on every failure so "it broke" becomes answerable.
  const requestId = crypto.randomUUID();

  try {
    return json({ products: await searchNrt(query, limit) });
  } catch (err) {
    if (err instanceof OpenFdaError) {
      // 429 is forwarded so the app can say "try again shortly". Everything
      // else becomes 502: the fault is upstream, and echoing openFDA's status
      // would imply this function was at fault.
      const status = err.status === 429 ? 429 : 502;
      console.error(`[${requestId}] openFDA lookup failed, upstream ${err.status ?? 'none'}`);
      return json(
        {
          // Not `err.message` — that names the endpoint and is written for
          // whoever runs the server, not for someone mid-craving.
          error: status === 429
            ? 'Too many lookups right now. Try again shortly.'
            : 'Product lookup is unavailable right now.',
          requestId,
        },
        status,
      );
    }

    console.error(`[${requestId}] Unexpected failure:`, err);
    return json({ error: 'Lookup failed.', requestId }, 500);
  }
}
