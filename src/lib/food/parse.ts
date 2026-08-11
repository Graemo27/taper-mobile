/**
 * Normalisation of FoodData Central's raw payloads.
 *
 * Three FDC quirks are handled here, all found by probing the live API:
 *  1. Search and detail return nutrients in *different shapes* — search is flat
 *     (`nutrientName`/`value`), detail is nested (`nutrient.name`/`amount`).
 *  2. Energy is listed twice on most foods, once in kcal and once in kJ. Matching
 *     on name alone silently yields kJ roughly half the time.
 *  3. Foundation foods routinely omit Energy altogether, so kcal must stay nullable
 *     rather than defaulting to 0 — a 0 would read as "this food has no calories".
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

/** Extracts the nutrient set we care about, per 100g. */
export function parseNutrients(raw: unknown[]): Nutrients {
  const flat = flatten(raw);
  const kcal = find(flat, 'Energy', 'kcal');
  return {
    // Unit-qualified: without it this returns kJ on foods that list both.
    kcal: kcal === null ? null : Math.round(kcal),
    proteinG: round1(find(flat, 'Protein', 'g')),
    fibreG: round1(find(flat, 'Fiber, total dietary', 'g')),
  };
}

/**
 * FDC portion labels come split across `amount`, `measureUnit.name` and `modifier`,
 * and `measureUnit.name` is very often the literal string "undetermined".
 */
function portionLabel(p: Record<string, any>): string {
  const amount: number = typeof p.amount === 'number' ? p.amount : 1;
  const unit = String(p.measureUnit?.name ?? '');
  const modifier = String(p.modifier ?? '').trim();
  const noun =
    unit && unit !== 'undetermined' ? unit : modifier || 'serving';
  const qualifier = unit && unit !== 'undetermined' && modifier ? ` (${modifier})` : '';
  const count = Number.isInteger(amount) ? String(amount) : String(amount);
  return `${count} ${noun}${qualifier}`.trim();
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
  };
}
