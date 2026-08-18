/**
 * The exclusion rules, tested where they live.
 *
 * These are the tests this module exists for. "NRT only, never a tobacco
 * product" has to be a property of the code rather than a promise in a
 * document, so the cases proving a pouch cannot come back are the point of the
 * file. They sit here rather than beside the handler because none of them is
 * about HTTP — a handler test that happened to cover them would be checking the
 * right behaviour through the wrong seam.
 *
 * Verified against the live endpoint on 2026-08-18: 'nicorette' returned gum at
 * 2 and 4 mg, 'nicoderm' patches at 21/14/7 mg, 'habitrol' lozenges at 2 and
 * 4 mg, and 'zyn', 'zonnic' and 'velo' each returned nothing.
 */

import { assertEquals, assertStringIncludes } from '@std/assert';
import { searchNrt } from './openfda.ts';

/** Replaces global fetch for one call, always restoring it. Returns the URLs requested. */
async function withFetch(
  reply: (url: string) => Response,
  run: () => Promise<void>,
): Promise<string[]> {
  const original = globalThis.fetch;
  const seen: string[] = [];
  globalThis.fetch = ((input: string | URL | Request) => {
    seen.push(String(input instanceof Request ? input.url : input));
    return Promise.resolve(reply(seen[seen.length - 1]));
  }) as typeof fetch;
  try {
    await run();
  } finally {
    globalThis.fetch = original;
  }
  return seen;
}

const ok = (body: unknown) =>
  new Response(JSON.stringify(body), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });

/** One openFDA NDC record, shaped as the live endpoint returns them. */
function record(over: Record<string, unknown> = {}) {
  return {
    product_ndc: '0135-0166',
    brand_name: 'Nicorette',
    labeler_name: 'GlaxoSmithKline',
    dosage_form: 'GUM, CHEWING',
    active_ingredients: [{ name: 'NICOTINE POLACRILEX', strength: '4 mg/1' }],
    ...over,
  };
}

Deno.test('a licensed product keeps its form and label mg', async () => {
  const urls = await withFetch(
    () => ok({ results: [record()] }),
    async () => {
      const [product] = await searchNrt('nicorette', 5);
      assertEquals(product.brand, 'Nicorette');
      assertEquals(product.form, 'gum');
      assertEquals(product.mg, 4);
      assertEquals(product.id, '0135-0166');
    },
  );
  assertStringIncludes(urls[0], 'api.fda.gov/drug/ndc.json');
});

Deno.test('every request is constrained to nicotine, whatever the caller asked for', async () => {
  const urls = await withFetch(() => ok({ results: [] }), async () => {
    await searchNrt('zyn', 5);
  });
  // The clause is a constant, not derived from input, so no query can drop it.
  assertStringIncludes(decodeURIComponent(urls[0]), 'active_ingredients.name:"nicotine"');
});

Deno.test('a caller cannot inject their way out of the nicotine clause', async () => {
  const urls = await withFetch(() => ok({ results: [] }), async () => {
    await searchNrt('x" OR dosage_form:"POUCH', 5);
  });
  const search = decodeURIComponent(urls[0]);
  assertStringIncludes(search, 'active_ingredients.name:"nicotine"');
  // Structural characters are stripped, not escaped: nothing typed may end a
  // term and start a new clause.
  assertEquals(search.includes('OR dosage_form:"POUCH"'), false);
  assertEquals(search.includes('"POUCH'), false);
});

Deno.test('a dosage form outside the five licensed ones is dropped', async () => {
  await withFetch(
    () => ok({ results: [record({ dosage_form: 'POUCH', brand_name: 'Not NRT' })] }),
    async () => assertEquals(await searchNrt('anything', 5), []),
  );
});

Deno.test('a record whose active ingredient is not nicotine is dropped', async () => {
  await withFetch(
    () =>
      ok({
        results: [record({ active_ingredients: [{ name: 'CAFFEINE', strength: '40 mg/1' }] })],
      }),
    async () => assertEquals(await searchNrt('anything', 5), []),
  );
});

Deno.test('a record with no readable mg is dropped rather than guessed at', async () => {
  await withFetch(
    () => ok({ results: [record({ active_ingredients: [{ name: 'NICOTINE', strength: '' }] })] }),
    async () => assertEquals(await searchNrt('anything', 5), []),
  );
});

Deno.test('patch strength keeps the dose, not the wear time', async () => {
  await withFetch(
    () =>
      ok({
        results: [
          record({
            dosage_form: 'PATCH, EXTENDED RELEASE',
            active_ingredients: [{ name: 'NICOTINE', strength: '21 mg/24 h' }],
          }),
        ],
      }),
    async () => {
      const [product] = await searchNrt('nicoderm', 5);
      assertEquals(product.form, 'patch');
      assertEquals(product.mg, 21);
    },
  );
});

Deno.test('the limit counts products kept, not rows fetched', async () => {
  await withFetch(
    () => ok({ results: [record({ dosage_form: 'POUCH' }), record(), record()] }),
    async () => assertEquals((await searchNrt('nicorette', 1)).length, 1),
  );
});

Deno.test('openFDA answers an empty result set with 404, which means no matches', async () => {
  await withFetch(
    () => new Response('{}', { status: 404 }),
    async () => assertEquals(await searchNrt('nicorette micro', 5), []),
  );
});

Deno.test('an upstream failure carries its status so the caller can map it', async () => {
  for (const status of [429, 500]) {
    await withFetch(
      () => new Response('nope', { status }),
      async () => {
        try {
          await searchNrt('nicorette', 5);
          throw new Error('expected a throw');
        } catch (err) {
          assertEquals((err as { status?: number }).status, status);
        }
      },
    );
  }
});
