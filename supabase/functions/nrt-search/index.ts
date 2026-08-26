/**
 * Entrypoint for the `nrt-search` Edge Function.
 *
 * One line of behaviour: `Deno.serve` at module scope means importing this file
 * starts a server, so everything worth testing lives in `handler.ts` and is
 * reached by calling `handle`.
 */

import { handle } from './handler.ts';

Deno.serve(handle);
