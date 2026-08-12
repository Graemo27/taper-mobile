/**
 * Presentation helpers shared by the results list and Food detail.
 *
 * Types only from the domain — nothing here may reach for `client.ts`, which
 * carries the FDC key and belongs to the Edge Function alone.
 */

import type { Portion } from './types.ts';

/**
 * A quantity opening a segment: "2", "0.5", "1/2", or the mixed "1 1/2".
 *
 * FDC writes all three. Reading only decimals does not merely miss the others —
 * it truncates at the slash and multiplies the numerator, turning "3/4 cup"
 * into "6/4 cup".
 */
function leadingQuantity(text: string): { value: number; rest: string } | null {
  const mixed = /^(\d+)\s+(\d+)\/(\d+)\s*/.exec(text);
  if (mixed) {
    const denominator = Number(mixed[3]);
    if (denominator === 0) return null;
    return {
      value: Number(mixed[1]) + Number(mixed[2]) / denominator,
      rest: text.slice(mixed[0].length),
    };
  }

  const fraction = /^(\d+)\/(\d+)\s*/.exec(text);
  if (fraction) {
    const denominator = Number(fraction[2]);
    if (denominator === 0) return null;
    return { value: Number(fraction[1]) / denominator, rest: text.slice(fraction[0].length) };
  }

  const decimal = /^(\d+(?:\.\d+)?)\s*/.exec(text);
  return decimal ? { value: Number(decimal[1]), rest: text.slice(decimal[0].length) } : null;
}

/**
 * Quotes, hyphens and slashes are how FDC writes dimensions and ranges —
 * `3-1/2" to 4" dia` on a bagel. Those describe the food; they are not a count
 * of it. Two bagels is not one bagel of twice the diameter, so a segment
 * shaped like that is left exactly as FDC wrote it.
 */
const DESCRIBES_RATHER_THAN_COUNTS = /["'\-/]/;

/**
 * "23 whole kernels" at two servings → "46 whole kernels".
 *
 * The design's detail line multiplies every quantity in the label, not just the
 * grams. FDC's nouns stay as written — "2 slice" rather than "2 slices" —
 * because pluralising needs a rule about English that holds for every food in
 * the database.
 */
function scaleSegment(segment: string, servings: number): string {
  if (servings === 1) return segment;

  const quantity = leadingQuantity(segment.trim());
  if (!quantity || DESCRIBES_RATHER_THAN_COUNTS.test(quantity.rest)) return segment;

  // Two decimals then back through Number, so 0.5 × 2 reads "1", not "1.00".
  const scaled = Number((quantity.value * servings).toFixed(2));
  return quantity.rest ? `${scaled} ${quantity.rest}` : String(scaled);
}

/**
 * "1 oz (23 whole kernels)" + 28.35g → "1 oz · 23 whole kernels · 28 g".
 *
 * The design sets the serving as middle-dot segments, and FDC already supplies
 * the split — its labels carry the count in a parenthetical. So this is a
 * reformat of real data, not a rewrite of it: the words stay FDC's ("23 whole
 * kernels", not the design's shorter "23 nuts"), because shortening them would
 * mean a synonym table that has to be right about every food in the database.
 */

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
