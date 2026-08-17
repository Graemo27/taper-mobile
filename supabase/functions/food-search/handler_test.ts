/**
 * Drives the whole request path against a stubbed `fetch`.
 *
 * This is the check the repository did not have. Until now the only ways to
 * exercise this function were `supabase functions serve` (Docker) or deploying
 * it (a production action), so two correct review findings were deferred for
 * want of any way to prove a change — see PRs #50 and #54. Stubbing the global
 * `fetch` runs the real handler, the real auth check, the real error mapping
 * and the real parser, on the runtime that actually serves it.
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
  return new Request('https://example.test/food-search', {
    method: 'POST',
    headers: auth ? { Authorization: `Bearer ${auth}` } : {},
    body: JSON.stringify(body),
  });
}

/** Replaces global fetch for one call, always restoring it. */
async function withFetch(
  reply: (url: string) => Response | Promise<Response>,
  run: () => Promise<void>,
): Promise<string[]> {
  const original = globalThis.fetch;
  const seen: string[] = [];
  globalThis.fetch = ((input: string | URL | Request) => {
    const url = String(input instanceof Request ? input.url : input);
    seen.push(url);
    return Promise.resolve(reply(url));
  }) as typeof fetch;
  try {
    await run();
  } finally {
    globalThis.fetch = original;
  }
  return seen;
}

const ok = (body: unknown) =>
  new Response(JSON.stringify(body), { status: 200, headers: { 'Content-Type': 'application/json' } });

const searchHit = {
  foods: [{ fdcId: 101, description: 'Almonds', dataType: 'SR Legacy', foodCategory: 'Nuts' }],
};

const detail = {
  fdcId: 101,
  description: 'Almonds',
  dataType: 'SR Legacy',
  foodNutrients: [
    { nutrient: { name: 'Energy', unitName: 'kcal' }, amount: 579 },
    { nutrient: { name: 'Protein', unitName: 'g' }, amount: 21.15 },
    { nutrient: { name: 'Fiber, total dietary', unitName: 'g' }, amount: 12.5 },
  ],
  foodPortions: [{ amount: 1, gramWeight: 28.35, measureUnit: { name: 'oz' } }],
};

Deno.env.set('FDC_API_KEY', 'test-key');

Deno.test('a search returns foods and the count FDC would not serve', async () => {
  await withFetch(
    (url) => ok(url.includes('/foods/search') ? searchHit : detail),
    async () => {
      const res = await handle(post({ query: 'almond', limit: 1 }));
      assertEquals(res.status, 200);
      const body = await res.json();
      assertEquals(body.foods.length, 1);
      assertEquals(body.foods[0].name, 'Almonds');
      assertEquals(body.foods[0].per100g.kcal, 579);
      assertEquals(body.unavailable, 0);
    },
  );
});

Deno.test('the anon key is rejected even though its signature is valid', async () => {
  // The legacy anon key ships inside every client build and is a correctly
  // signed JWT, so `verify_jwt` passes it. It carries role "anon" and no sub.
  const res = await handle(post({ query: 'almond' }, token({ role: 'anon' })));
  assertEquals(res.status, 401);
  assertEquals((await res.json()).error, 'Sign in required.');
});

// The two halves of that guard are asserted separately below, because the
// realistic anon token fails both at once: a test using it alone stays green
// even if the role check is deleted, which is how the first version of this
// file was written.

Deno.test('role alone is not enough: "anon" with a subject is still rejected', async () => {
  const res = await handle(post({ query: 'a' }, token({ role: 'anon', sub: 'user-1' })));
  assertEquals(res.status, 401);
});

Deno.test('a subject alone is not enough: "authenticated" without one is rejected', async () => {
  const res = await handle(post({ query: 'a' }, token({ role: 'authenticated' })));
  assertEquals(res.status, 401);
});

Deno.test('a malformed token is rejected rather than throwing', async () => {
  for (const bad of ['', 'not-a-jwt', 'a.b', 'a.!!!not-base64!!!.c']) {
    assertEquals((await handle(post({ query: 'a' }, bad))).status, 401, bad);
  }
});

Deno.test('an anonymous user is accepted, because it is a real account', async () => {
  await withFetch(
    (url) => ok(url.includes('/foods/search') ? searchHit : detail),
    async () => {
      const res = await handle(post({ query: 'almond', limit: 1 }));
      assertEquals(res.status, 200);
    },
  );
});

Deno.test('a missing Authorization header is rejected', async () => {
  assertEquals((await handle(post({ query: 'a' }, null))).status, 401);
});

Deno.test('input validation answers before any FDC request is made', async () => {
  const cases: Array<[unknown, number, string]> = [
    [{}, 400, 'A query is required.'],
    [{ query: '   ' }, 400, 'A query is required.'],
    [{ query: 'a', limit: 0 }, 400, 'limit must be an integer from 1 to 10.'],
    [{ query: 'a', limit: 11 }, 400, 'limit must be an integer from 1 to 10.'],
    [{ query: 'a', limit: 1.5 }, 400, 'limit must be an integer from 1 to 10.'],
    [{ fdcId: 0 }, 400, 'fdcId must be a positive integer.'],
    [{ fdcId: -3 }, 400, 'fdcId must be a positive integer.'],
    [{ fdcId: 'abc' }, 400, 'fdcId must be a positive integer.'],
  ];
  for (const [body, status, error] of cases) {
    const calls = await withFetch(
      () => ok({}),
      async () => {
        const res = await handle(post(body));
        assertEquals(res.status, status, `${JSON.stringify(body)} -> ${res.status}`);
        assertEquals((await res.json()).error, error);
      },
    );
    assertEquals(calls.length, 0, `${JSON.stringify(body)} should not reach FDC`);
  }
});

Deno.test('a body carrying both fdcId and query takes the id, and never searches', async () => {
  const calls = await withFetch(
    () => ok(detail),
    async () => {
      const res = await handle(post({ fdcId: 101, query: 'almond' }));
      assertEquals(res.status, 200);
      assertEquals((await res.json()).food.fdcId, 101);
    },
  );
  assertEquals(calls.filter((u) => u.includes('/foods/search')).length, 0);
});

Deno.test('upstream statuses map to what the app can act on', async () => {
  const cases: Array<[number, number, string]> = [
    [404, 404, 'That food is no longer in the USDA database.'],
    [429, 429, 'Too many lookups right now. Try again shortly.'],
    [500, 502, 'Food lookup is unavailable right now.'],
    [403, 502, 'Food lookup is unavailable right now.'],
  ];
  for (const [upstream, expected, message] of cases) {
    await withFetch(
      () => new Response('upstream said no', { status: upstream }),
      async () => {
        const res = await handle(post({ fdcId: 101 }));
        assertEquals(res.status, expected, `FDC ${upstream}`);
        const body = await res.json();
        assertEquals(body.error, message);
        // Every failure carries a correlation id and never FDC's own wording,
        // which is operator advice about setting FDC_API_KEY.
        assertEquals(typeof body.requestId, 'string');
      },
    );
  }
});

Deno.test('a 404 on one row of a search drops that row rather than the result', async () => {
  await withFetch(
    (url) => {
      if (url.includes('/foods/search')) {
        return ok({
          foods: [
            { fdcId: 101, description: 'Almonds', dataType: 'SR Legacy' },
            { fdcId: 999, description: 'Ghost', dataType: 'SR Legacy' },
          ],
        });
      }
      return url.includes('999') ? new Response('gone', { status: 404 }) : ok(detail);
    },
    async () => {
      const res = await handle(post({ query: 'almond', limit: 2 }));
      assertEquals(res.status, 200);
      const body = await res.json();
      assertEquals(body.foods.length, 1);
      assertEquals(body.unavailable, 1);
    },
  );
});

Deno.test('a 429 on one row fails the whole search, unlike a 404', async () => {
  await withFetch(
    (url) =>
      url.includes('/foods/search')
        ? ok(searchHit)
        : new Response('slow down', { status: 429 }),
    async () => {
      const res = await handle(post({ query: 'almond', limit: 1 }));
      assertEquals(res.status, 429);
    },
  );
});

Deno.test('non-POST and preflight are answered without touching FDC', async () => {
  const options = await handle(
    new Request('https://example.test/food-search', { method: 'OPTIONS' }),
  );
  assertEquals(options.status, 200);
  assertEquals(options.headers.get('Access-Control-Allow-Origin'), '*');

  const get = await handle(new Request('https://example.test/food-search', { method: 'GET' }));
  assertEquals(get.status, 405);
});

Deno.test('a non-JSON body is rejected before the request id is minted', async () => {
  const res = await handle(
    new Request('https://example.test/food-search', {
      method: 'POST',
      headers: { Authorization: `Bearer ${user}` },
      body: 'not json',
    }),
  );
  assertEquals(res.status, 400);
  assertEquals((await res.json()).error, 'Body must be JSON.');
});

Deno.test('the FDC key never reaches the response, on success or failure', async () => {
  await withFetch(
    () => new Response('boom', { status: 500 }),
    async () => {
      const res = await handle(post({ fdcId: 101 }));
      const text = await res.text();
      assertEquals(text.includes('test-key'), false);
      assertStringIncludes(text, 'requestId');
    },
  );
});

Deno.test('JSON that is valid but not an object is rejected, not crashed on', async () => {
  // `await req.json()` happily returns null, [] or "abc". Only the parse is
  // inside the try, so a null body reaches `body.fdcId` and throws there.
  for (const raw of ['null', '[]', '"abc"', '42', 'true']) {
    const res = await handle(
      new Request('https://example.test/food-search', {
        method: 'POST',
        headers: { Authorization: `Bearer ${user}` },
        body: raw,
      }),
    );
    assertEquals(res.status, 400, `body ${raw} -> ${res.status}`);
    assertEquals((await res.json()).error, 'Body must be JSON.');
  }
});
