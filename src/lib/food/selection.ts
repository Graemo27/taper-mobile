/**
 * The hand-off between Search and Food detail.
 *
 * Search has already resolved the whole `Food` — name, portions, nutrients —
 * and the Edge Function exposes one route, `POST {query, limit}`, with no
 * fetch-by-id. So detail either re-fetches through a route that does not exist
 * yet, or it is handed the object the previous screen already holds. This is
 * the second.
 *
 * The cost is deliberate and bounded: a cold load of `/food/123` — a reload, or
 * a link from outside the app — has no object to find, and the screen says so
 * rather than rendering an empty shell. Nothing links into this route yet, so
 * the only way to reach that state today is a manual refresh. When deep links
 * matter, the fix is a get-by-id route on the function, not a bigger cache.
 *
 * Route params cannot carry this instead: they are strings, and serialising a
 * `Food` through the URL would put a nutrient table in the address bar.
 */

import type { Food } from './types.ts';

let selected: Food | null = null;

export function selectFood(food: Food): void {
  selected = food;
}

/**
 * Guarded by id so a stale selection cannot answer for a different food — if
 * the route asks for one id and the held object is another, that is a miss.
 * Non-consuming, because React may render the screen more than once.
 */
export function selectedFood(fdcId: number): Food | null {
  return selected && selected.fdcId === fdcId ? selected : null;
}
