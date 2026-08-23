/**
 * The exclusion rules, tested where they live rather than through the handler:
 * none of them is a property of HTTP. "NRT only, never a tobacco product" has to
 * hold in the code, not just in a document.
 *
 * These stubs prove this module, not openFDA. Driven live on 2026-08-18:
 * 'nicorette' gave gum at 2 and 4 mg, 'nicoderm' patches at 21/14/7 mg,
 * 'habitrol' lozenges at 2 and 4 mg; 'zyn', 'zonnic' and 'velo' gave nothing.
 */

import { assertEquals, assertRejects, assertStringIncludes } from '@std/assert';
import { OpenFdaError, searchNrt } from './openfda.ts';

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

Deno.test('no input can drop the nicotine clause or append one of its own', async () => {
  for (const term of ['zyn', 'x" OR dosage_form:"POUCH', '']) {
    const urls = await withFetch(() => ok({ results: [] }), async () => {
      await searchNrt(term, 5);
    });
    const search = decodeURIComponent(urls[0]);
    // The clause is a constant, not derived from input.
    assertStringIncludes(search, 'active_ingredients.name:"nicotine"');
    // Structural characters are stripped, not escaped: nothing typed may end a
    // term and start a new clause.
    assertEquals(search.includes('"POUCH'), false);
  }
});

Deno.test('anything that is not unambiguously licensed NRT is dropped', async () => {
  const rejected: Record<string, unknown>[] = [
    // A tobacco product, were one ever to reach this code.
    { dosage_form: 'POUCH', brand_name: 'Not NRT' },
    // The four nicotine dosage forms openFDA really does carry besides the
    // licensed ones: bulk raw nicotine registered by the kilogram (POWDER,
    // LIQUID), homeopathic pellets, and one patch mislabelled as a lotion.
    // None is a cessation product a user may put on a key, and each must stay
    // dropped whatever the allowlist is matching on.
    { dosage_form: 'POWDER', brand_name: 'Nicotine', active_ingredients: [{ name: 'NICOTINE', strength: '1 kg/kg' }] },
    { dosage_form: 'LIQUID', brand_name: 'Tobacco Withdrawal' },
    { dosage_form: 'PELLET', brand_name: 'Nicotinum' },
    { dosage_form: 'LOTION', brand_name: 'Nicotine Patches' },
    // A drug that is not nicotine.
    { active_ingredients: [{ name: 'CAFFEINE', strength: '40 mg/1' }] },
    // Nicotine, but no readable dose — dropped rather than guessed at.
    { active_ingredients: [{ name: 'NICOTINE', strength: '' }] },
    { product_ndc: '' },
    { brand_name: '' },
  ];
  for (const over of rejected) {
    await withFetch(
      () => ok({ results: [record(over)] }),
      async () => assertEquals(await searchNrt('anything', 5), []),
    );
  }
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

Deno.test('the limit counts products kept, and a bad one is clamped not forwarded', async () => {
  await withFetch(
    () => ok({ results: [record({ dosage_form: 'POUCH' }), record(), record()] }),
    async () => {
      assertEquals((await searchNrt('nicorette', 1)).length, 1);
      // A fractional limit would never equal a row count, so the loop has to
      // stop on the clamped value or it returns every over-fetched row.
      assertEquals((await searchNrt('nicorette', 1.5)).length, 1);
    },
  );
  for (const [limit, sent] of [[0, '4'], [-3, '4'], [2.7, '8'], [999, '100']] as const) {
    const urls = await withFetch(() => ok({ results: [] }), async () => {
      await searchNrt('nicorette', limit);
    });
    assertEquals(new URL(urls[0]).searchParams.get('limit'), sent);
  }
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
        const err = await assertRejects(() => searchNrt('nicorette', 5), OpenFdaError);
        assertEquals(err.status, status);
      },
    );
  }
});

Deno.test('a 200 carrying something other than JSON is an upstream fault, not a crash', async () => {
  await withFetch(
    () => new Response('<html>maintenance</html>', { status: 200 }),
    async () => {
      const err = await assertRejects(() => searchNrt('nicorette', 5), OpenFdaError);
      assertEquals(err.status, 200);
    },
  );
});

Deno.test('an unreachable openFDA never puts the request URL in the error', async () => {
  Deno.env.set('OPENFDA_API_KEY', 'super-secret-value');
  try {
    await withFetch(
      () => {
        // Deno reports a fetch failure with the full URL, which carries the key.
        throw new TypeError(
          'error sending request for url (https://api.fda.gov/drug/ndc.json?api_key=super-secret-value)',
        );
      },
      async () => {
        const err = await assertRejects(() => searchNrt('nicorette', 5), OpenFdaError);
        assertEquals(err.message.includes('super-secret-value'), false);
        assertEquals(err.message, 'openFDA unreachable');
      },
    );
  } finally {
    Deno.env.delete('OPENFDA_API_KEY');
  }
});
