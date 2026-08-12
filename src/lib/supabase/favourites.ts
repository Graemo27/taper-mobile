/**
 * Favourites, held in one place the whole app reads from.
 *
 * Two screens care: Food detail sets them, the results list shows them. Fetching
 * separately in each would leave the list stale the moment you starred something
 * and went back, so the set lives here and both subscribe to it.
 *
 * The store is optimistic — the star flips immediately and rolls back if the
 * write fails. A bookmark that lags a round trip feels broken in a way that a
 * saved journal entry does not, because you are usually starring several.
 */

import { useSyncExternalStore } from 'react';

import { supabase } from './client.ts';
import { ensureSession } from './session.ts';

let ids: ReadonlySet<number> = new Set();
let loaded = false;
const listeners = new Set<() => void>();

/** Replaced rather than mutated, so `useSyncExternalStore` sees a new snapshot. */
function commit(next: ReadonlySet<number>): void {
  ids = next;
  for (const listener of listeners) listener();
}

function subscribe(listener: () => void): () => void {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

/** The set of favourited fdcIds, re-rendering whatever reads it when it changes. */
export function useFavourites(): ReadonlySet<number> {
  return useSyncExternalStore(
    subscribe,
    () => ids,
    () => ids,
  );
}

/**
 * Fills the store once per launch. Safe to call from anywhere on mount; later
 * calls are ignored so a screen re-entry does not re-fetch.
 */
export async function loadFavourites(): Promise<void> {
  if (loaded) return;
  loaded = true;

  const userId = await ensureSession();
  const { data, error } = await supabase.from('favourites').select('fdc_id').eq('user_id', userId);

  // A failed load leaves the set empty: nothing is shown as favourited, which
  // is wrong but quiet, and the next launch tries again.
  if (error) {
    loaded = false;
    return;
  }

  commit(new Set((data ?? []).map((row) => row.fdc_id as number)));
}

export async function toggleFavourite(fdcId: number): Promise<void> {
  const wasOn = ids.has(fdcId);

  const next = new Set(ids);
  if (wasOn) next.delete(fdcId);
  else next.add(fdcId);
  commit(next);

  const userId = await ensureSession();
  const { error } = wasOn
    ? await supabase.from('favourites').delete().eq('user_id', userId).eq('fdc_id', fdcId)
    : await supabase.from('favourites').insert({ user_id: userId, fdc_id: fdcId });

  // Put it back rather than leaving a star that claims a row that is not there.
  if (error) {
    const reverted = new Set(ids);
    if (wasOn) reverted.add(fdcId);
    else reverted.delete(fdcId);
    commit(reverted);
  }
}
