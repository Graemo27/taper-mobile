/**
 * Which nutrients a food is high in.
 *
 * "High in" is the FDA's term for a nutrient supplying 20% or more of its Daily
 * Value in one serving; 10–19% is "good source". The design labels this section
 * "Rich in" and shows five chips for almonds, which is the 10% bar — at 20%
 * almonds has one. The stricter bar is used, and the heading renamed to match
 * it, because the alternative is a claim the number does not support.
 *
 * Unsaturated fat is in the design and not here. There is no Daily Value for
 * it, so there is nothing to be 20% of. Any threshold would be invented, and an
 * invented threshold in a nutrition app is the thing this file exists to avoid.
 * The honest version of that chip is a different sentence — almonds are 88%
 * unsaturated by fat, which is a proportion, not a quantity — so it wants its
 * own design rather than a smuggled-in rule.
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
  { label: 'Protein', read: (n) => n.proteinG, dailyValue: 50 },
];

const HIGH_IN = 0.2;

/**
 * Takes one standard serving, never the stepped count.
 *
 * The claim describes the food, not the plate. Scaling it with the stepper
 * would make anything high in everything at enough servings, which is how you
 * turn a fact into a compliment.
 */
export function highIn(perServing: Nutrients): string[] {
  return CLAIMS.filter((claim) => {
    const amount = claim.read(perServing);
    // Null is a gap in FDC's data, not a zero, and neither one qualifies.
    return amount !== null && amount >= claim.dailyValue * HIGH_IN;
  }).map((claim) => claim.label);
}
