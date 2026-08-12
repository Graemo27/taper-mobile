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
/**
 * How the lookup failed. The Search screen picks its state from this.
 *
 * A discriminator rather than an absent `status`, because these are three
 * mutually exclusive outcomes and encoding one of them as "the other field
 * happens to be undefined" is how a timeout ended up wearing the offline
 * message.
 */
export type FoodSearchFailure = 'http' | 'timeout' | 'offline';

export class FoodSearchError extends Error {
  /** Present when the server assigned one — quote it in a bug report. */
  requestId: string | undefined;

  kind: FoodSearchFailure;

  /** Only meaningful when `kind` is `'http'`; the server answered with it. */
  status: number | undefined;

  constructor(
    message: string,
    kind: FoodSearchFailure,
    status?: number,
    requestId?: string,
  ) {
    super(message);
    this.name = 'FoodSearchError';
    this.kind = kind;
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
      // Parsed as unknown, not asserted into a shape. `as { error?: string }`
      // is a claim, not a check: a gateway body of `{ error: { message } }` is
      // truthy, so it would reach the constructor and `super()` would render
      // the user a literal "[object Object]".
      const body: unknown = await context.json();
      if (typeof body === 'object' && body !== null) {
        const { error: message, requestId } = body as {
          error?: unknown;
          requestId?: unknown;
        };
        if (typeof message === 'string' && message !== '') {
          return new FoodSearchError(
            message,
            'http',
            context.status,
            typeof requestId === 'string' ? requestId : undefined,
          );
        }
      }
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
    return new FoodSearchError(
      'Food lookup is unavailable right now.',
      'http',
      context.status,
    );
  }

  // functions-js implements `timeout` with an AbortController, then wraps the
  // rejection — `fetch(...).catch(e => { throw new FunctionsFetchError(e) })`.
  // So the abort never arrives by its own name: what lands here is a
  // FunctionsFetchError carrying the AbortError on `.context`. Checking the
  // outer name misses it and a 15s timeout claims the network is down.
  //
  // Confirmed against the live function at `timeout: 1`, because the previous
  // attempt at this checked a shape the SDK does not produce. A real network
  // failure wraps a TypeError, not an AbortError, so this cannot swallow one.
  //
  // The bare check stays as well, in case a later version stops wrapping.
  //
  // Every abort is ours today because `searchFoods` accepts no AbortSignal.
  // When the Search screen starts cancelling a stale request on each keystroke
  // that stops being true, and cancellation will need telling apart from this.
  const aborted =
    (error instanceof Error && error.name === 'AbortError') ||
    (typeof context === 'object' &&
      context !== null &&
      (context as { name?: unknown }).name === 'AbortError');

  if (aborted) {
    return new FoodSearchError('Food search took too long.', 'timeout');
  }

  // No response, and we did not give up — the request never got out.
  return new FoodSearchError(
    'Could not reach food search. Check your connection.',
    'offline',
  );
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
  // The finite check is not decoration: `Math.trunc(NaN)` is `NaN`, and `NaN`
  // survives both `Math.max` and `Math.min`, serialises to `null`, and comes
  // back as the 400 this clamp exists to prevent.
  const rows = Math.min(10, Math.max(1, Number.isFinite(limit) ? Math.trunc(limit) : 5));

  const { data, error } = await supabase.functions.invoke<SearchResult>('food-search', {
    body: { query: trimmed, limit: rows },
    // Without this a stalled request never settles and the Search screen holds
    // its loading skeleton forever. Live searches measure 2–3s.
    timeout: 15_000,
  });

  if (error) throw await describe(error);
  // A success with no body. Same thing as a 5xx from where the user sits, so it
  // gets the same words rather than a second phrasing for one condition.
  if (!data) throw new FoodSearchError('Food lookup is unavailable right now.', 'http');

  return data;
}

/**
 * One food, by id, for the screens that hold a reference rather than the food.
 *
 * A `/food/123` route reached by a reload has no hand-off to read — see
 * `lib/food/selection.ts` — and a journal row records an fdcId, not a nutrient
 * table. Both need this.
 *
 * A 404 arrives as a `FoodSearchError` with `status: 404` and the server's own
 * wording, which callers can tell apart from an outage: a food that is not
 * there is an answer, and offering Try again for it would be a loop.
 */
export async function fetchFood(fdcId: number): Promise<Food> {
  // The function answers 400 for anything else, in text written for whoever
  // calls the API — the same reason `limit` is clamped above rather than sent
  // as given. Here it cannot be clamped into something sensible, so it is
  // refused in the shape callers already handle.
  if (!Number.isSafeInteger(fdcId) || fdcId <= 0) {
    throw new FoodSearchError('That food could not be found.', 'http', 404);
  }

  await ensureSession();

  const { data, error } = await supabase.functions.invoke<{ food: Food }>('food-search', {
    body: { fdcId },
    // One FDC request rather than the search path's six, but the same ceiling:
    // what it guards against is a request that never settles, not a slow one.
    timeout: 15_000,
  });

  if (error) throw await describe(error);
  if (!data?.food) throw new FoodSearchError('Food lookup is unavailable right now.', 'http');

  return data.food;
}
