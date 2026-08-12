/**
 * Which nutrients a food is dense in, per 100 g.
 *
 * **This is a density statement, not an FDA nutrient content claim.** The
 * distinction matters and the first version got it wrong. A regulatory "high
 * in" claim is measured against the Reference Amount Customarily Consumed for
 * the food's category, not against whatever portion we happen to display.
 * Measuring against `pickPortion` — a heuristic for picking a readable serving
 * — inflated the result: fdcId 174284, raw red lentils, offers one 192 g cup,
 * which is dry weight that cooks into several servings. Against it the food
 * scored three claims; against the 35 g dry-legume RACC it scores none.
 *
 * We have no RACC table, so we do not make that claim. 100 g is a fixed basis
 * that belongs to the food rather than to a guess about the plate, which is
 * also the only basis on which "this food is dense in X" stays true no matter
 * how much of it someone logs.
 *
 * The 20% figure is still the FDA's Daily Value proportion, because a Daily
 * Value is a real reference and an invented one would not be.
 *
 * Two of the design's five chips are deliberately absent:
 *
 * - **Unsaturated fat** has no Daily Value, so there is nothing to take 20% of.
 * - **Protein** needs correcting by its digestibility score (PDCAAS) before it
 *   can be expressed as a percentage — 21 CFR 101.9(c)(7). FDC gives raw grams
 *   only, so a low-quality protein would score the same as a complete one.
 *
 * Both want data or a design we do not have. Inventing a rule for either is the
 * thing this file exists to avoid.
 */

import type { Nutrients } from './types.ts';

/** FDA Daily Values for adults, 2016 labelling rules. */
interface Claim {
  label: string;
  read: (nutrients: Nutrients) => number | null;
  dailyValue: number;
}

const CLAIMS: readonly Claim[] = [
  { label: 'Vitamin E', read: (n) => n.vitaminEMg, dailyValue: 15 },
  { label: 'Magnesium', read: (n) => n.magnesiumMg, dailyValue: 420 },
  { label: 'Fibre', read: (n) => n.fibreG, dailyValue: 28 },
];

const DENSE = 0.2;

/**
 * Takes per-100g nutrients — never a portion, and never the stepped count.
 *
 * Both would make the answer depend on how much of the food is in front of you
 * rather than on the food, and at enough servings everything is high in
 * everything, which is how you turn a fact into a compliment.
 */
export function highIn(per100g: Nutrients): string[] {
  return CLAIMS.filter((claim) => {
    const amount = claim.read(per100g);
    // Null is a gap in FDC's data, not a zero, and neither one qualifies.
    return amount !== null && amount >= claim.dailyValue * DENSE;
  }).map((claim) => claim.label);
}
