/**
 * Drives the whole request path against a stubbed `fetch`.
 *
 * Scoped to what is genuinely about HTTP — auth, input validation, and how an
 * upstream failure is reported. The exclusion rules that give this function its
 * reason to exist are tested in `nrt/openfda_test.ts`, against the module that
 * enforces them, because none of them is a property of the request path.
 */

import { assertEquals, assertStringIncludes } from '@std/assert';
import { handle } from './handler.ts';

/** Minimal well-formed JWT. Only the payload is read; the signature is never checked here. */
function token(claims: Record<string, unknown>): string {
  const b64url = (o: unknown) =>
    btoa(JSON.stringify(o)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  return `${b64url({ alg: 'HS256', typ: 'JWT' })}.${b64url(claims)}.signature`;
}

const user = token({ role: 'authenticated', sub: 'user-1', is_anonymous: true });

function post(body: unknown, auth: string | null = user): Request {
  return new Request('https://example.test/nrt-search', {
    method: 'POST',
    headers: auth ? { Authorization: `Bearer ${auth}` } : {},
    body: JSON.stringify(body),
  });
}

/** Replaces global fetch for one call, always restoring it. Returns the URLs requested. */
async function withFetch(reply: () => Response, run: () => Promise<void>): Promise<string[]> {
  const original = globalThis.fetch;
  const seen: string[] = [];
  globalThis.fetch = ((input: string | URL | Request) => {
    seen.push(String(input instanceof Request ? input.url : input));
    return Promise.resolve(reply());
  }) as typeof fetch;
  try {
    await run();
  } finally {
    globalThis.fetch = original;
  }
  return seen;
}

const hit = {
  results: [
    {
      product_ndc: '0135-0166',
      brand_name: 'Nicorette',
      labeler_name: 'GlaxoSmithKline',
      dosage_form: 'GUM, CHEWING',
      active_ingredients: [{ name: 'NICOTINE POLACRILEX', strength: '4 mg/1' }],
    },
  ],
};

const ok = () =>
  new Response(JSON.stringify(hit), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });

Deno.test('a search returns products', async () => {
  await withFetch(ok, async () => {
    const res = await handle(post({ query: 'nicorette', limit: 5 }));
    assertEquals(res.status, 200);
    const body = await res.json();
    assertEquals(body.products.length, 1);
    assertEquals(body.products[0].form, 'gum');
  });
});

Deno.test('an upstream failure is reported as upstream, never as the caller’s fault', async () => {
  await withFetch(() => new Response('nope', { status: 500 }), async () => {
    const res = await handle(post({ query: 'nicorette' }));
    assertEquals(res.status, 502);
    const body = await res.json();
    assertStringIncludes(body.error, 'unavailable');
    // The operator-facing message names the endpoint; the user-facing one must not.
    assertEquals(body.error.includes('openFDA'), false);
    assertEquals(typeof body.requestId, 'string');
  });
});

Deno.test('rate limiting is forwarded so the app can say try again', async () => {
  await withFetch(() => new Response('slow down', { status: 429 }), async () => {
    assertEquals((await handle(post({ query: 'nicorette' }))).status, 429);
  });
});

Deno.test('a request without a user session is refused', async () => {
  assertEquals((await handle(post({ query: 'nicorette' }, null))).status, 401);
});

Deno.test('the anon key is not a user session', async () => {
  assertEquals((await handle(post({ query: 'x' }, token({ role: 'anon' })))).status, 401);
});

Deno.test('input is validated before anything is fetched', async () => {
  const urls = await withFetch(ok, async () => {
    assertEquals((await handle(post({ query: '   ' }))).status, 400);
    assertEquals((await handle(post({ query: 'ok', limit: 0 }))).status, 400);
    assertEquals((await handle(post({ query: 'ok', limit: 99 }))).status, 400);
    assertEquals((await handle(post({ query: 'ok', limit: 1.5 }))).status, 400);
    assertEquals((await handle(post(null))).status, 400);
    assertEquals((await handle(post([]))).status, 400);
  });
  assertEquals(urls.length, 0);
});

Deno.test('non-POST and preflight are answered without touching openFDA', async () => {
  const urls = await withFetch(ok, async () => {
    assertEquals((await handle(new Request('https://x.test', { method: 'GET' }))).status, 405);
    const pre = await handle(new Request('https://x.test', { method: 'OPTIONS' }));
    assertEquals(pre.status, 200);
    assertEquals(pre.headers.get('Access-Control-Allow-Origin'), '*');
  });
  assertEquals(urls.length, 0);
});
