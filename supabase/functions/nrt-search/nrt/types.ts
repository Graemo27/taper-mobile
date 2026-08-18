/**
 * The shape the app receives, and the allowlist that defines it.
 *
 * Kept separate from the fetching so the exclusion rule can be read in one
 * place: if a form is not in `FORMS`, no request path can produce it.
 */

/** A licensed nicotine replacement product, reduced to what a pad key needs. */
export interface NrtProduct {
  /** openFDA `product_ndc`. Stable enough to store on a key and re-look-up. */
  id: string;
  brand: string;
  labeler: string;
  form: NrtForm;
  /** Label milligrams per unit — per piece, or per 24h for a patch. */
  mg: number;
}

/**
 * The five licensed delivery forms, and nothing else.
 *
 * This is the second of two guarantees. The first is the data source: openFDA's
 * drug endpoint holds drugs, and pouches and vapes are regulated as tobacco
 * products, so they are absent by construction rather than by filtering. This
 * allowlist is the backstop for anything nicotine-bearing that *is* a drug but
 * is not a cessation product — an unmapped dosage form is dropped, so a new
 * form appearing upstream fails closed rather than open.
 */
export type NrtForm = 'gum' | 'lozenge' | 'patch' | 'inhaler' | 'spray';

/**
 * openFDA `dosage_form` strings are uppercase and comma-qualified — "GUM,
 * CHEWING", "PATCH, EXTENDED RELEASE" — so matching is by keyword rather than
 * equality. Order matters only in that each keyword is unique to one form.
 */
export const FORMS: ReadonlyArray<readonly [string, NrtForm]> = [
  ['GUM', 'gum'],
  ['LOZENGE', 'lozenge'],
  ['TROCHE', 'lozenge'],
  ['PATCH', 'patch'],
  ['FILM, EXTENDED RELEASE', 'patch'],
  ['INHAL', 'inhaler'],
  ['SPRAY', 'spray'],
];
