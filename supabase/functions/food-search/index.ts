/**
 * Entrypoint for the `food-search` Edge Function.
 *
 * Deliberately one line of behaviour. `Deno.serve` at module scope means that
 * importing this file starts a server, so everything worth testing lives in
 * `handler.ts` and is reached by calling `handle` with a `Request`. Splitting
 * it this way rather than guarding the serve call keeps the deployed runtime's
 * behaviour identical: this module is still the entrypoint, and it still serves
 * unconditionally.
 */

import { handle } from './handler.ts';

Deno.serve(handle);
