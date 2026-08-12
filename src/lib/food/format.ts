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
 * "1/6 of 16 oz cake" — the number is a share of another thing, not a count of
 * this one, and the slash that would have caught it was eaten by the fraction
 * parser. Doubling the portion does not make it a third of the cake; it makes
 * it two pieces, which the segment in front of this one already says.
 */
const SHARE_OF_SOMETHING_ELSE = /^of\b/i;

/**
 * "1 can, 15 oz (303 x 406)" — a can's dimension code, where 303 is a diameter
 * in thirty-seconds of an inch. Two cans are not one can of 606, and the x has
 * no plural. It arrives here because the guard above looks for punctuation and
 * this separator is a letter.
 */
const DIMENSION_PAIR = /^x\b/i;

/**
 * Words that are counted but never pluralised.
 *
 * Units, because "2 ozs" is not a thing anyone writes, and the sizes FDC uses
 * as a portion in their own right — "1 medium" is a whole banana, and two of
 * them are "2 medium", not "2 mediums".
 */
const UNCOUNTED = new Set([
  'cal',
  'cm',
  'fl',
  'g',
  'gal',
  'in',
  'kcal',
  'kg',
  'l',
  'lb',
  'mg',
  'ml',
  'mm',
  'oz',
  'pt',
  'qt',
  'tbsp',
  'tsp',
  // Sizes, which FDC writes with the noun left out.
  'extra',
  'cubic',
  'each',
  'jumbo',
  'large',
  'medium',
  'mini',
  'regular',
  'small',
  'thick',
  'thin',
]);

/**
 * The plurals no rule gets right.
 *
 * -oes is the trap: potato and tomato take it, and taco, burrito and avocado —
 * every one of them a word English borrowed — do not. Rather than guess at the
 * etymology of a noun, the three that take it are named and everything else
 * ending in o takes a plain s.
 */
const IRREGULAR: Record<string, string> = {
  half: 'halves',
  leaf: 'leaves',
  loaf: 'loaves',
  mango: 'mangoes',
  potato: 'potatoes',
  tomato: 'tomatoes',
};

/**
 * A rule rather than a list of nouns, because the list was measurably too
 * short: written against the labels twenty searches returned, it already missed
 * "1 pita, large" on the next food tried. Foods are not a closed set, and a
 * dictionary of them would go on being incomplete.
 *
 * The lists above are not closed either — each grew when the rule was run over
 * a hundred and thirty-nine real labels and read back. What makes them workable
 * is that they hold words about *portions*, of which there are few, rather than
 * words about *food*, of which there is no end.
 */
function plural(word: string): string {
  const known = IRREGULAR[word];
  if (known) return known;

  // Sibilants take -es: sandwiches, dishes, boxes. Not -s, which is here
  // because a label can already be plural — FDC writes "4 slices" — and
  // "8 sliceses" was what this produced before that turned up in real data.
  if (/(x|z|ch|sh)$/.test(word)) return `${word}es`;
  // Consonant then y takes -ies: patties. A vowel first does not: trays.
  if (/[^aeiou]y$/.test(word)) return `${word.slice(0, -1)}ies`;
  return `${word}s`;
}

/**
 * The counted noun, and everything that is not it.
 *
 * Usually the first word — "slice, thin" and "cup shredded" both name the thing
 * before describing it. But FDC also writes the size first and the noun second,
 * "1 small bagel", where pluralising nothing leaves "2 small bagel" and
 * pluralising the size gives "2 smalls". So a leading size hands over to the
 * word behind it, and a size with nothing behind it — "1 small" is a whole
 * cookie — stays as it is.
 *
 * Trailing punctuation is kept: "slice," has to come back as "slices,". Case is
 * kept too, for the capitalised nouns FDC writes, like "1 Figaroo".
 */
function precedesTheNoun(word: string): boolean {
  const bare = word.replace(/\W+$/, '');
  // An acronym is a qualifier, never the thing counted: FDC writes "1 NLEA
  // serving", where the servings are what there are two of, not the NLEAs.
  return UNCOUNTED.has(bare.toLowerCase()) || (bare.length > 1 && bare === bare.toUpperCase());
}

function pluralised(rest: string): string {
  const words = rest.split(' ');
  const at = words[0] && precedesTheNoun(words[0]) ? 1 : 0;

  const parsed = /^([A-Za-z]+)(\W*)$/.exec(words[at] ?? '');
  if (!parsed) return rest;

  const word = parsed[1];
  const lower = word.toLowerCase();
  // A qualifier in second place is still a qualifier, and a word already plural
  // is done.
  if (precedesTheNoun(word) || lower.endsWith('s')) return rest;

  const suffixed = plural(lower);
  const cased =
    word[0] === word[0].toUpperCase() ? suffixed[0].toUpperCase() + suffixed.slice(1) : suffixed;

  return words.map((each, index) => (index === at ? cased + parsed[2] : each)).join(' ');
}

/**
 * "23 whole kernels" at two servings → "46 whole kernels".
 *
 * The design's detail line multiplies every quantity in the label, not just the
 * grams. The noun follows the number: two of a one-slice portion is "2 slices",
 * and leaving it at "2 slice" was a defect visible on the screen.
 */
function scaleSegment(segment: string, servings: number): string {
  if (servings === 1) return segment;

  const quantity = leadingQuantity(segment.trim());
  if (!quantity || DESCRIBES_RATHER_THAN_COUNTS.test(quantity.rest)) return segment;
  if (SHARE_OF_SOMETHING_ELSE.test(quantity.rest)) return segment;
  if (DIMENSION_PAIR.test(quantity.rest)) return segment;

  // Two decimals then back through Number, so 0.5 × 2 reads "1", not "1.00".
  const scaled = Number((quantity.value * servings).toFixed(2));
  if (!quantity.rest) return String(scaled);

  // Anything that is not exactly one takes the plural, halves included: "0.5
  // cups" is what English does, however odd it looks next to "1 cup".
  return `${scaled} ${scaled === 1 ? quantity.rest : pluralised(quantity.rest)}`;
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

/**
 * FDC restates the serving inside some labels — `1 slice 1 serving`,
 * `0.99 oz 1 serving`. It is redundant beside the card's own "2 servings"
 * title, and it is a second count that would go stale the moment the first one
 * scaled, since it counts servings rather than slices.
 */
const RESTATED_SERVING = /\s+\d+(?:\.\d+)?\s+servings?$/i;

export function servingSummary(portion: Portion | null, servings = 1): string {
  if (!portion) return `${100 * servings} g`;

  const label = portion.label.replace(RESTATED_SERVING, '');
  const match = /^(.*?)\s*\((.*)\)\s*$/.exec(label);
  // A label opening on its parenthetical gives an empty first group and a
  // leading " · ". `parse.ts` always prefixes an amount so that cannot arrive
  // today, but the `Portion` type promises nothing about the string.
  const parts = (match ? [match[1], match[2]] : [label]).filter((part) => part.trim() !== '');
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
