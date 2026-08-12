/**
 * Normalisation of FoodData Central's raw payloads.
 *
 * Four FDC quirks handled here, all found by probing the live API:
 *  0. Portion labels carry labelling jargon — "1 RACC", "1 NLEA serving" —
 *     which is accurate and unreadable. See `withoutJargon` and `portionLabel`.
 *  1. Search returns nutrients flat (`nutrientName`/`value`), detail nested
 *     (`nutrient.name`/`amount`).
 *  2. Energy is listed twice per food, kcal and kJ — matching on name alone
 *     silently yields kJ about half the time.
 *  3. Foundation foods routinely omit Energy, so kcal stays nullable; a 0 would
 *     read as "this food has no calories".
 */

import type { Nutrients, Portion } from './types.ts';

interface FlatNutrient {
  name: string;
  unit: string;
  value: number | null;
}

/** Collapses both FDC nutrient shapes into one. */
function flatten(raw: unknown[]): FlatNutrient[] {
  return raw.map((entry) => {
    const n = entry as Record<string, any>;
    const nested = n.nutrient as Record<string, any> | undefined;
    return {
      name: String(nested?.name ?? n.nutrientName ?? ''),
      unit: String(nested?.unitName ?? n.unitName ?? ''),
      value: typeof n.amount === 'number' ? n.amount : (n.value ?? null),
    };
  });
}

function find(
  nutrients: FlatNutrient[],
  name: string,
  unit?: string,
): number | null {
  const hit = nutrients.find(
    (n) =>
      n.name.toLowerCase() === name.toLowerCase() &&
      (unit === undefined || n.unit.toLowerCase() === unit.toLowerCase()),
  );
  return hit?.value ?? null;
}

/** Rounds to one decimal. FDC reports absurd precision, e.g. 20.78734 g protein. */
function round1(v: number | null): number | null {
  return v === null ? null : Math.round(v * 10) / 10;
}

/**
 * Mono plus poly, which is what "unsaturated fat" means on the design's chip.
 *
 * Both halves or nothing. Absent is not zero, and half an answer is worse than
 * none: fdcId 2647443 (Cheese, cotija) is a real Foundation record listing
 * monounsaturated with no polyunsaturated row, so counting the missing half as
 * zero would publish a lower bound as though it were the total.
 *
 * A row that reports 0 is a reading rather than a gap — `find` returns null
 * only when the row is absent — so genuine zeroes still come through.
 */
function unsaturatedFat(nutrients: FlatNutrient[]): number | null {
  const mono = find(nutrients, 'Fatty acids, total monounsaturated', 'g');
  const poly = find(nutrients, 'Fatty acids, total polyunsaturated', 'g');
  if (mono === null || poly === null) return null;
  return round1(mono + poly);
}

/** Extracts the nutrient set we care about, per 100g. */
export function parseNutrients(raw: unknown[]): Nutrients {
  const flat = flatten(raw);
  const kcal = find(flat, 'Energy', 'kcal');
  return {
    // Unit-qualified: without it this returns kJ on foods that list both.
    kcal: kcal === null ? null : Math.round(kcal),
    proteinG: round1(find(flat, 'Protein', 'g')),
    fibreG: round1(find(flat, 'Fiber, total dietary', 'g')),
    // FDC's full name. "Vitamin E" alone also matches added-tocopherol rows on
    // some foods, which are a different measurement.
    vitaminEMg: round1(find(flat, 'Vitamin E (alpha-tocopherol)', 'mg')),
    magnesiumMg: round1(find(flat, 'Magnesium, Mg', 'mg')),
    unsaturatedFatG: unsaturatedFat(flat),
  };
}

/**
 * Strips FDC's labelling jargon from a modifier, keeping whatever is left.
 *
 * NLEA is the Nutrition Labeling and Education Act, and "1 NLEA serving" means
 * "one serving as that act defines it" — true, and no use to someone deciding
 * what they just ate.
 *
 * FDC nests it inside the modifier's own parentheses, sometimes alongside
 * something worth keeping, so deleting the phrase alone leaves the brackets and
 * the separator behind:
 *
 *   "cup (1 NLEA serving)"                        → "cup"
 *   "serving (1 NLEA serving - about 4 crackers)" → "serving (about 4 crackers)"
 *
 * Hence the tidy-up passes: a parenthetical emptied by the removal goes with it,
 * and a separator left dangling against a bracket goes too.
 */
function withoutJargon(modifier: string): string {
  return modifier
    .replace(/\d+(?:\.\d+)?\s*NLEA\s+servings?/gi, '')
    // A separator now leaning on either bracket belonged to the phrase.
    .replace(/\(\s*[-–—,;]*\s*/g, '(')
    .replace(/\s*[-–—,;]*\s*\)/g, ')')
    // Whatever that leaves empty was only ever holding the phrase.
    .replace(/\(\s*\)/g, '')
    .replace(/\s{2,}/g, ' ')
    .replace(/^[\s\-–—,;]+/, '')
    .replace(/[\s\-–—,;]+$/, '')
    .trim();
}

/**
 * FDC portion labels come split across `amount`, `measureUnit.name` and `modifier`,
 * and `measureUnit.name` is very often the literal string "undetermined".
 */
function portionLabel(p: Record<string, any>): string {
  // FDC sometimes reports amount 0 alongside a real gramWeight — fdcId 171300
  // lists `amount: 0.0, modifier: "container (4 oz)", gramWeight: 113`, which
  // rendered as "0 container (4 oz)". Zero is a number, so a typeof-only guard
  // let it through. A portion that weighs something is at least one of itself.
  const raw = p.amount;
  const amount: number = typeof raw === 'number' && raw > 0 ? raw : 1;
  const unit = String(p.measureUnit?.name ?? '');
  const modifier = withoutJargon(String(p.modifier ?? '').trim());
  // "RACC" is the Reference Amount Customarily Consumed. It names a reference
  // rather than a thing you can picture, and "1 RACC" was reaching readers
  // verbatim, so it is treated as an unnamed unit like "undetermined" is.
  const named = unit !== '' && unit !== 'undetermined' && unit.toUpperCase() !== 'RACC';
  const noun = named ? unit : modifier || 'serving';
  // Not repeated as a qualifier when it is already carrying the noun.
  const qualifier = named && modifier ? ` (${modifier})` : '';
  return `${amount} ${noun}${qualifier}`.trim();
}

export function parsePortions(raw: unknown[]): Portion[] {
  return raw
    .map((entry) => {
      const p = entry as Record<string, any>;
      const grams = typeof p.gramWeight === 'number' ? p.gramWeight : null;
      return grams && grams > 0
        ? { label: portionLabel(p), grams }
        : null;
    })
    .filter((p): p is Portion => p !== null);
}

/**
 * Picks the portion that best represents "one serving".
 *
 * FDC lists portions in no particular order and mixes scales wildly — almonds
 * offer "1 almond" (1.2g) alongside "1 cup, whole" (143g). Preferring a
 * plausible eating quantity avoids both extremes.
 */
export function pickPortion(portions: Portion[]): Portion | null {
  if (portions.length === 0) return null;
  const inBand = (lo: number, hi: number) =>
    portions.find((p) => p.grams >= lo && p.grams <= hi);
  return inBand(20, 150) ?? inBand(10, 300) ?? portions[0];
}

/** Scales per-100g nutrients to a portion. Nulls stay null rather than becoming 0. */
export function scaleTo(per100g: Nutrients, grams: number): Nutrients {
  const factor = grams / 100;
  const scale = (v: number | null) =>
    v === null ? null : Math.round(v * factor * 10) / 10;
  return {
    kcal: per100g.kcal === null ? null : Math.round(per100g.kcal * factor),
    proteinG: scale(per100g.proteinG),
    fibreG: scale(per100g.fibreG),
    vitaminEMg: scale(per100g.vitaminEMg),
    magnesiumMg: scale(per100g.magnesiumMg),
    unsaturatedFatG: scale(per100g.unsaturatedFatG),
  };
}
