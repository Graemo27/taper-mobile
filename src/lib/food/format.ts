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
/**
 * "23 whole kernels" at two servings → "46 whole kernels".
 *
 * The design's detail line multiplies every quantity in the label, not just the
 * grams. A segment with no leading number is left exactly as it is, and so are
 * FDC's nouns — "2 slice" rather than "2 slices". Pluralising would need a rule
 * about English that is right for every food in the database, and the words are
 * already FDC's by the decision above.
 */
function scaleSegment(segment: string, servings: number): string {
  if (servings === 1) return segment;

  const match = /^(\d+(?:\.\d+)?)(\s*)(.*)$/.exec(segment.trim());
  if (!match) return segment;

  // Two decimals then back through Number, so 0.5 × 2 reads "1", not "1.00".
  const scaled = Number((Number(match[1]) * servings).toFixed(2));
  return `${scaled}${match[2]}${match[3]}`;
}

export function servingSummary(portion: Portion | null, servings = 1): string {
  if (!portion) return `${100 * servings} g`;

  const match = /^(.*?)\s*\((.*)\)\s*$/.exec(portion.label);
  // A label opening on its parenthetical gives an empty first group and a
  // leading " · ". `parse.ts` always prefixes an amount so that cannot arrive
  // today, but the `Portion` type promises nothing about the string.
  const parts = (match ? [match[1], match[2]] : [portion.label]).filter(
    (part) => part.trim() !== '',
  );
  // Grams scale from the true weight and round once at the end, so two 28.35 g
  // servings read 57 g rather than the 56 g that rounding first would give.
  return [
    ...parts.map((part) => scaleSegment(part, servings)),
    `${Math.round(portion.grams * servings)} g`,
  ].join(' · ');
}

/** Grams carry a unit, energy does not — the design labels it underneath. */
export function grams(value: number | null): string {
  return value === null ? '—' : `${Math.round(value)}g`;
}

export function energy(value: number | null): string {
  return value === null ? '—' : String(Math.round(value));
}
