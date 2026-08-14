/**
 * Food search proxy.
 *
 * Exists because the FDC key cannot ship to the client. Any key inside a client
 * build is extractable from any install — this was written when Expo inlined
 * `EXPO_PUBLIC_*` into the JS bundle, and a native build is no better, only
 * less convenient to unpack. USDA deactivates keys it finds published. So the
 * key lives here as a Supabase secret and the app never sees it.
 *
 * The whole N+1 fan-out runs server-side: a five-row result costs six requests.
 * Doing that from the device would mean six round trips over mobile network
 * instead of one, and would leak the shape of the quota to anyone watching.
 *
 * **The fan-out itself is not necessary, and this comment used to claim it
 * was.** `GET /v1/foods?fdcIds=…` returns full records *including*
 * `foodPortions`, for Foundation and SR Legacy alike — measured against the
 * live API on 2026-08-14. The original claim is true only of
 * `format=abridged`, which does omit portions and is the likely source of the
 * mistake. Collapsing search + N lookups into two requests is a real
 * improvement and deliberately not made here: it changes behaviour in a
 * deployed function, and this repository still cannot drive an Edge Function
 * locally to prove it. See the follow-up on PR #54.
 *
 * The lookup logic lives in `./food` rather than inline. It was originally
 * split out to be shared with a Node harness (`npm run food`) that exercised it
 * without deploying; that harness went with the React Native app in PR #53. The
 * split is kept because it is still the only way to read this logic without a
 * request handler wrapped around it.
 *
 * `./food` sat at `src/lib/food/` until PR #50, inside the app that PR #53 then
 * deleted. Moving it first is the only reason deleting the app did not quietly
 * take the backend's lookup logic with it — the deployed function would have
 * kept serving from its existing bundle, and the loss would have surfaced at
 * some later redeploy with nothing to connect it to.
 */

import { FdcError, getFood, searchWithServings } from './food/index.ts';

/**
 * Retained from the Expo build, which also targeted web and so preflighted.
 * The native client does not, but `supabase functions serve` and any browser
 * used to poke at this still do, and removing headers is a behaviour change
 * with no upside.
 */
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

/**
 * Turns a thrown lookup into the response the app reads.
 *
 * Shared by both routes: a food that FDC will not serve fails the same way
 * whether it was reached by name or by id, and two copies of this would drift.
 */
function failure(err: unknown, requestId: string): Response {
  if (err instanceof FdcError) {
    // A by-id lookup can genuinely ask for a food that is not there — a stale
    // journal row, a hand-typed URL — and that is the caller's answer, not an
    // outage. 429 is forwarded so the app can say "try again shortly" rather
    // than "no such food". Everything else becomes 502: the failure is
    // upstream, and echoing FDC's status would imply this function was at
    // fault.
    const status = err.status === 404 ? 404 : err.status === 429 ? 429 : 502;
    console.error(`[${requestId}] FDC lookup failed, upstream ${err.status ?? 'none'}: ${err.message}`);
    return json(
      {
        // Not `err.message`. FdcError is written for whoever runs the server —
        // it names the FDC endpoint and tells the reader to set FDC_API_KEY.
        // That is operator advice, and it has no business inside a food app.
        error:
          status === 404
            ? 'That food is no longer in the USDA database.'
            : status === 429
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

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'Use POST.' }, 405);

  if (!userId(req)) {
    return json({ error: 'Sign in required.' }, 401);
  }

  let body: { query?: unknown; limit?: unknown; fdcId?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'Body must be JSON.' }, 400);
  }

  // Correlates a user's report with a log line without the log holding what
  // they typed. Returned on every failure so "it broke" becomes answerable.
  const requestId = crypto.randomUUID();

  // One food, by id. What the app has when it holds a reference to a food but
  // not the food itself: a journal row it wants to reopen, or a `/food/123`
  // route reached by a reload, where search has never run.
  //
  // Checked before `query` rather than after, so a body carrying both is not
  // silently searched — a caller sending both means one of them is a mistake.
  if (body.fdcId !== undefined) {
    const fdcId = Number(body.fdcId);
    if (!Number.isSafeInteger(fdcId) || fdcId <= 0) {
      return json({ error: 'fdcId must be a positive integer.' }, 400);
    }

    try {
      return json({ food: await getFood(fdcId) });
    } catch (err) {
      return failure(err, requestId);
    }
  }

  const query = typeof body.query === 'string' ? body.query.trim() : '';
  if (query === '') return json({ error: 'A query is required.' }, 400);

  // Capped, not just validated. Each row costs an FDC request against a shared
  // quota, so an unbounded limit is a way to exhaust it from one device.
  const raw = body.limit === undefined ? 5 : Number(body.limit);
  if (!Number.isSafeInteger(raw) || raw < 1 || raw > 10) {
    return json({ error: 'limit must be an integer from 1 to 10.' }, 400);
  }

  try {
    const { foods, unavailable } = await searchWithServings(query, raw);
    return json({ foods, unavailable });
  } catch (err) {
    return failure(err, requestId);
  }
});
