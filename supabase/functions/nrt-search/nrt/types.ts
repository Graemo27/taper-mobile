/**
 * The shape the app receives, and the allowlist that defines it. Kept apart from
 * the fetching so the exclusion rule reads in one place: if a form is not in
 * `FORMS`, no request path can produce it.
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
 * The five licensed delivery forms, and nothing else. The backstop behind the
 * data source itself: openFDA's drug endpoint holds drugs, so tobacco products
 * are absent by construction, and this catches anything nicotine-bearing that
 * *is* a drug but is not a cessation product. An unmapped form is dropped, so a
 * new one upstream fails closed.
 */
export type NrtForm = 'gum' | 'lozenge' | 'patch' | 'inhaler' | 'spray';

/**
 * Whole base forms, spelled as openFDA spells them. Its `dosage_form` grammar is
 * `BASE` or `BASE, QUALIFIER` — "GUM, CHEWING", "PATCH, EXTENDED RELEASE" — so
 * one entry covers a family's qualifiers and nothing else. Every entry is a
 * complete base rather than a stem: a stem would match by spelling instead of
 * by meaning, and "GUM" would take in "GUMMY".
 */
export const FORMS: ReadonlyArray<readonly [string, NrtForm]> = [
  ['GUM', 'gum'],
  ['LOZENGE', 'lozenge'],
  ['TROCHE', 'lozenge'],
  ['PATCH', 'patch'],
  ['FILM, EXTENDED RELEASE', 'patch'],
  ['INHALANT', 'inhaler'],
  ['SPRAY', 'spray'],
];
