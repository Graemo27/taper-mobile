/**
 * Domain types for food lookup. Deliberately narrower than FoodData Central's
 * response shape — FDC is the current source, but nothing outside `lib/food`
 * should know that.
 */

/** A household measure for one serving, e.g. "1 oz (23 whole kernels)" at 28.35g. */
export interface Portion {
  /** Human-readable, shown verbatim in the UI. */
  label: string;
  grams: number;
}

/**
 * A nutrient set. Every field is nullable because FDC coverage is uneven —
 * Foundation foods frequently omit Energy entirely.
 */
export interface Nutrients {
  kcal: number | null;
  proteinG: number | null;
  fibreG: number | null;
}

/** A search result. Carries no serving data — FDC's search endpoint returns none. */
export interface FoodHit {
  fdcId: number;
  name: string;
  category: string | null;
  /** FDC dataset: "Foundation" | "SR Legacy" | "Branded" | "Survey (FNDDS)". */
  dataType: string;
}

/** A fully resolved food, from the detail endpoint. */
export interface Food extends FoodHit {
  /** Best household serving, or null when FDC lists no usable portion. */
  portion: Portion | null;
  per100g: Nutrients;
  /** Scaled to `portion`. Null when there is no portion to scale to. */
  perServing: Nutrients | null;
  /** Every portion FDC lists, for a unit picker later. */
  portions: Portion[];
}
