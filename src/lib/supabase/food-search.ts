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

  constructor(message: string, requestId?: string) {
    super(message);
    this.name = 'FoodSearchError';
    this.requestId = requestId;
  }
}

/** Pulls the function's `{ error, requestId }` body out of a failed invoke. */
async function describe(error: unknown): Promise<FoodSearchError> {
  const context: unknown = (error as { context?: unknown }).context;

  if (context instanceof Response) {
    try {
      const body = (await context.json()) as { error?: string; requestId?: string };
      if (body.error) return new FoodSearchError(body.error, body.requestId);
    } catch {
      // Non-JSON body — fall through to the generic message below.
    }
  }

  // Covers the offline case, where invoke rejects before any response exists.
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

  const { data, error } = await supabase.functions.invoke<SearchResult>('food-search', {
    body: { query: trimmed, limit },
  });

  if (error) throw await describe(error);
  if (!data) throw new FoodSearchError('Food search returned nothing.');

  return data;
}
