/**
 * The hand-off between Search and Food detail.
 *
 * Search has already resolved the whole `Food` — name, portions, nutrients —
 * so handing it over saves a round trip in front of a tap that has nothing left
 * to fetch. That is all this is now: an optimisation, not the only route.
 *
 * A miss is no longer a dead end. `POST {fdcId}` on the function fetches the
 * food, and Food detail falls through to it — a reload, a link from outside the
 * app, or a screen that holds an id rather than a food. This stays because the
 * common path should not pay for the uncommon one.
 *
 * Route params cannot carry this instead: they are strings, and serialising a
 * `Food` through the URL would put a nutrient table in the address bar.
 */

import type { Food } from '../../../supabase/functions/food-search/food/types.ts';

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
