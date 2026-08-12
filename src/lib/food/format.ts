/**
 * Presentation helpers shared by the results list and Food detail.
 *
 * Types only from the domain — nothing here may reach for `client.ts`, which
 * carries the FDC key and belongs to the Edge Function alone.
 */

import type { Portion } from './types.ts';

/**
 * "1 oz (23 whole kernels)" + 28.35g → "1 oz · 23 whole kernels · 28 g".
 *
 * The design sets the serving as middle-dot segments, and FDC already supplies
 * the split — its labels carry the count in a parenthetical. So this is a
 * reformat of real data, not a rewrite of it: the words stay FDC's ("23 whole
 * kernels", not the design's shorter "23 nuts"), because shortening them would
 * mean a synonym table that has to be right about every food in the database.
 */
export function servingSummary(portion: Portion | null): string {
  if (!portion) return '100 g';

  const match = /^(.*?)\s*\((.*)\)\s*$/.exec(portion.label);
  // A label opening on its parenthetical gives an empty first group and a
  // leading " · ". `parse.ts` always prefixes an amount so that cannot arrive
  // today, but the `Portion` type promises nothing about the string.
  const parts = (match ? [match[1], match[2]] : [portion.label]).filter(
    (part) => part.trim() !== '',
  );
  return [...parts, `${Math.round(portion.grams)} g`].join(' · ');
}

/** Grams carry a unit, energy does not — the design labels it underneath. */
export function grams(value: number | null): string {
  return value === null ? '—' : `${Math.round(value)}g`;
}

export function energy(value: number | null): string {
  return value === null ? '—' : String(Math.round(value));
}
