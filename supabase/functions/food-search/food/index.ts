/**
 * Food lookup. The only module the rest of the app should import from.
 *
 * FDC splits what the UI needs across two endpoints: search returns candidates
 * with per-100g nutrients and *no* serving sizes, detail returns household
 * portions. Rendering a search list with per-serving figures therefore costs one
 * request per row — see `searchWithServings`.
 */

import { FdcError, fdcFetch } from './client.ts';
import { parseNutrients, parsePortions, pickPortion, scaleTo } from './parse.ts';
import type { Food, FoodHit } from './types.ts';

export { FdcError } from './client.ts';
export type { Food, FoodHit, Nutrients, Portion } from './types.ts';

/** Whole and lightly-processed foods. Branded is excluded — it is barcode data. */
const DATA_TYPES = 'Foundation,SR Legacy';

export async function searchFoods(
  query: string,
  limit = 5,
  signal?: AbortSignal,
): Promise<FoodHit[]> {
  if (query.trim() === '') return [];

  const res = await fdcFetch<{ foods?: unknown[] }>(
    '/foods/search',
    { query, pageSize: limit, dataType: DATA_TYPES },
    signal,
  );

  return (res.foods ?? []).map((entry) => {
    const f = entry as Record<string, any>;
    return {
      fdcId: Number(f.fdcId),
      name: String(f.description ?? ''),
      category: f.foodCategory ? String(f.foodCategory) : null,
      dataType: String(f.dataType ?? ''),
    };
  });
}

export async function getFood(
  fdcId: number,
  signal?: AbortSignal,
): Promise<Food> {
  const f = await fdcFetch<Record<string, any>>(`/food/${fdcId}`, {}, signal);

  const per100g = parseNutrients(f.foodNutrients ?? []);
  const portions = parsePortions(f.foodPortions ?? []);
  const portion = pickPortion(portions);

  return {
    fdcId: Number(f.fdcId),
    name: String(f.description ?? ''),
    category: f.foodCategory?.description
      ? String(f.foodCategory.description)
      : (f.foodCategory ? String(f.foodCategory) : null),
    dataType: String(f.dataType ?? ''),
    portion,
    portions,
    per100g,
    perServing: portion ? scaleTo(per100g, portion.grams) : null,
  };
}

/**
 * Search, then resolve each hit to get its serving.
 *
 * This is N+1 requests as written, not by necessity. `GET /v1/foods?fdcIds=…`
 * returns full records including `foodPortions` — verified against the live API
 * on 2026-08-14 for both Foundation and SR Legacy — so this could be two
 * requests rather than `limit + 1`. Only `format=abridged` omits portions,
 * which is where the older "no batch endpoint" claim came from. Batching is a
 * pending change, not a rejected one; it needs a way to drive this function
 * locally first. Until then keep `limit` small. DEMO_KEY (30 req/hour) will not
 * survive repeated use; set FDC_API_KEY.
 *
 * Note that batching would also change the failure model below: a per-id 404
 * currently identifies exactly which row FDC would not serve, and one batched
 * response would have to derive that from which ids came back missing.
 *
 * Failures are split by kind, because the two obvious policies are both wrong:
 * dropping everything turns a 429 into a misleading "no such food", while
 * rejecting on anything lets one bad row kill a good result set.
 *
 *  - 404 — FDC's search index lists a food its detail store will not serve.
 *    A data gap, not a query failure: the row is dropped and counted.
 *  - everything else — auth, rate limit, network, abort — is systemic and
 *    rejects the whole lookup.
 */
export async function searchWithServings(
  query: string,
  limit = 5,
  signal?: AbortSignal,
): Promise<{ foods: Food[]; unavailable: number }> {
  const hits = await searchFoods(query, limit, signal);
  const settled = await Promise.allSettled(
    hits.map((h) => getFood(h.fdcId, signal)),
  );

  const systemic = settled.find(
    (r): r is PromiseRejectedResult =>
      r.status === 'rejected' &&
      !(r.reason instanceof FdcError && r.reason.status === 404),
  );
  if (systemic) throw systemic.reason;

  const foods = settled
    .filter((r): r is PromiseFulfilledResult<Food> => r.status === 'fulfilled')
    .map((r) => r.value);

  return { foods, unavailable: hits.length - foods.length };
}
