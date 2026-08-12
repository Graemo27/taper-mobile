/**
 * App-side food search — the only way the UI reaches FoodData Central.
 *
 * Deliberately not in `src/lib/food/`: that directory is uploaded to Deno by
 * `supabase functions deploy` and runs server-side. This runs on the device.
 * Only the *types* cross the boundary, and types are erased, so importing them
 * pulls nothing into the function bundle.
 */

import type { Food } from '../food/types.ts';
import { supabase } from './client.ts';
import { ensureSession } from './session.ts';

export interface SearchResult {
  foods: Food[];
  /** Rows FDC listed in search but would not serve from its detail store. */
  unavailable: number;
}

/**
 * A failure the UI can show a person.
 *
 * `message` is always safe to render: the function returns text written for
 * users, never the FdcError text written for whoever runs the server.
 */
export class FoodSearchError extends Error {
  /** Present when the server assigned one — quote it in a bug report. */
  requestId: string | undefined;

  /**
   * HTTP status, or undefined when the request never reached the server.
   *
   * The Search screen picks its copy from this: 429 and 502 have their own
   * designed states, and `undefined` is the offline one.
   */
  status: number | undefined;

  constructor(message: string, status?: number, requestId?: string) {
    super(message);
    this.name = 'FoodSearchError';
    this.status = status;
    this.requestId = requestId;
  }
}

/** Pulls the function's `{ error, requestId }` body out of a failed invoke. */
async function describe(error: unknown): Promise<FoodSearchError> {
  const context: unknown =
    typeof error === 'object' && error !== null
      ? (error as { context?: unknown }).context
      : undefined;

  if (context instanceof Response) {
    try {
      const body = (await context.json()) as { error?: string; requestId?: string };
      if (body.error) return new FoodSearchError(body.error, context.status, body.requestId);
    } catch {
      // Non-JSON body — a crash before our handler, or a gateway error.
    }

    // A response came back, so the network is fine and this is the server's
    // fault. Falling through to the connection message here would tell someone
    // to check their wifi while they are plainly online.
    //
    // No requestId: ours travels in the body, and we just failed to read it.
    // Supabase's gateway `x-request-id` is a different namespace from the one
    // our logs record, so quoting it would hand over a code that matches
    // nothing. Better no reference than a wrong one.
    return new FoodSearchError('Food lookup is unavailable right now.', context.status);
  }

  // No response at all — invoke rejected before one existed.
  return new FoodSearchError('Could not reach food search. Check your connection.');
}

/**
 * Searches foods, signing in anonymously first if needed.
 *
 * `limit` costs one FDC request per row server-side, so it is a real budget
 * rather than a page size — the default matches what the Search screen shows.
 */
export async function searchFoods(query: string, limit = 5): Promise<SearchResult> {
  const trimmed = query.trim();
  // Saves a round trip, and the function would reject it anyway.
  if (!trimmed) return { foods: [], unavailable: 0 };

  await ensureSession();

  // Clamped to the range the function accepts. Out of range it answers 400
  // with "limit must be an integer from 1 to 10." — text written for whoever
  // calls the API, which has no business being rendered to a user. A caller's
  // mistake should not become user-facing copy.
  const rows = Math.min(10, Math.max(1, Math.trunc(limit)));

  const { data, error } = await supabase.functions.invoke<SearchResult>('food-search', {
    body: { query: trimmed, limit: rows },
    // Without this a stalled request never settles and the Search screen holds
    // its loading skeleton forever. Live searches measure 2–3s.
    timeout: 15_000,
  });

  if (error) throw await describe(error);
  if (!data) throw new FoodSearchError('Food search returned nothing.');

  return data;
}
