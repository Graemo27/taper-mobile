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
 *
 * That optimism is what makes the rest of this file careful. The star is live
 * while the first load is still in flight, and it can be pressed faster than
 * the network answers, so three things are guarded: a slow load must not
 * overwrite a newer press, presses on one food must not overtake each other,
 * and a failure of any kind must put the star back.
 */

import { useEffect } from 'react';
import { useSyncExternalStore } from 'react';

import { supabase } from './client.ts';
import { ensureSession } from './session.ts';

let ids: ReadonlySet<number> = new Set();
const listeners = new Set<() => void>();

/** Resolved once the initial fetch has succeeded. Until then it may retry. */
let loaded = false;
let loading: Promise<void> | null = null;

/**
 * Presses made while the initial load is in flight, as fdcId → intended state.
 * The load applies these on top of what it fetched, so a star pressed at launch
 * survives the answer to a query that was sent before it.
 */
let pressedDuringLoad: Map<number, boolean> | null = null;

/** One chain per food, so two presses on the same star cannot land out of order. */
const chains = new Map<number, Promise<void>>();

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

function withFood(base: ReadonlySet<number>, fdcId: number, on: boolean): Set<number> {
  const next = new Set(base);
  if (on) next.add(fdcId);
  else next.delete(fdcId);
  return next;
}

/**
 * Fills the store once per launch, and is safe to call from anywhere.
 *
 * `loaded` is only set after the fetch actually succeeds. Marking it up front
 * would mean an auth failure at launch could never be retried — the app would
 * show an empty set until it was restarted.
 */
export function loadFavourites(): Promise<void> {
  if (loaded) return Promise.resolve();
  if (loading) return loading;

  pressedDuringLoad = new Map();

  loading = (async () => {
    try {
      const userId = await ensureSession();
      const { data, error } = await supabase
        .from('favourites')
        .select('fdc_id')
        .eq('user_id', userId);
      if (error) throw error;

      let next: ReadonlySet<number> = new Set((data ?? []).map((row) => row.fdc_id as number));
      // Anything pressed while this was in flight is newer than the answer.
      for (const [fdcId, on] of pressedDuringLoad ?? []) next = withFood(next, fdcId, on);

      commit(next);
      loaded = true;
    } catch {
      // Left unloaded on purpose: nothing is shown as favourited, which is
      // wrong but quiet, and the next screen to mount tries again.
    } finally {
      pressedDuringLoad = null;
      loading = null;
    }
  })();

  return loading;
}

/**
 * The set of favourited fdcIds, re-rendering whatever reads it when it changes.
 *
 * Reading the store is what triggers the load, so no screen has to remember to
 * ask. The results list needs this as much as Food detail does — before, the
 * fetch only ran on detail, and stars were invisible until you opened one.
 */
export function useFavourites(): ReadonlySet<number> {
  useEffect(() => {
    void loadFavourites();
  }, []);

  return useSyncExternalStore(
    subscribe,
    () => ids,
    () => ids,
  );
}

async function write(fdcId: number): Promise<void> {
  const on = !ids.has(fdcId);

  commit(withFood(ids, fdcId, on));
  pressedDuringLoad?.set(fdcId, on);

  try {
    const userId = await ensureSession();
    // Idempotent on purpose. Before the first load lands the store reads empty,
    // so a press on an already-favourited food means "add" and a plain insert
    // would collide with the row that is already there — failing, and rolling
    // the star back to a state the database disagrees with. A delete of a row
    // that is not there is a no-op already.
    //
    // `ignoreDuplicates` matters: it compiles to ON CONFLICT DO NOTHING. The
    // default upsert is ON CONFLICT DO UPDATE, which needs an update privilege
    // this table deliberately does not grant, so it fails the policy and rolls
    // the star back — measured, not assumed.
    const { error } = on
      ? await supabase
          .from('favourites')
          .upsert(
            { user_id: userId, fdc_id: fdcId },
            { onConflict: 'user_id,fdc_id', ignoreDuplicates: true },
          )
      : await supabase.from('favourites').delete().eq('user_id', userId).eq('fdc_id', fdcId);
    if (error) throw error;
  } catch {
    // Any failure, not just a query error — a rejected sign-in leaves the write
    // undone just the same, and a star that claims a row nobody wrote is worse
    // than one that never moved.
    commit(withFood(ids, fdcId, !on));
    pressedDuringLoad?.set(fdcId, !on);
  }
}

/**
 * Never rejects: callers fire this from a press handler and the store owns the
 * failure, so there is nothing useful for a screen to catch.
 */
export function toggleFavourite(fdcId: number): Promise<void> {
  // Queued behind any press still in flight for this food. Without it, a double
  // tap sends an insert and a delete that can complete in either order and
  // leave the database disagreeing with the star.
  const chained = (chains.get(fdcId) ?? Promise.resolve()).then(
    () => write(fdcId),
    () => write(fdcId),
  );

  chains.set(fdcId, chained);
  void chained.finally(() => {
    if (chains.get(fdcId) === chained) chains.delete(fdcId);
  });

  return chained;
}
