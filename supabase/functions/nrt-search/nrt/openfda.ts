/**
 * openFDA NDC directory lookup, restricted to licensed NRT.
 *
 * The NDC endpoint is used rather than the drug label one because it carries
 * `active_ingredients[].strength` as a field. A pad key needs a number, and
 * parsing "each piece contains 4 mg of nicotine" out of label prose would be a
 * guess dressed up as data.
 *
 * No API key is required. openFDA rate-limits anonymous callers by IP, which is
 * why this runs server-side: one function's IP is a known quantity, where every
 * device having its own would be untraceable when the limit bites. An optional
 * `OPENFDA_API_KEY` secret raises the ceiling and is never required.
 */

import { FORMS, type NrtProduct } from './types.ts';

const BASE = 'https://api.fda.gov/drug/ndc.json';

/** An openFDA failure, carrying the upstream status so the caller can map it. */
export class OpenFdaError extends Error {
  status: number | undefined;

  constructor(message: string, status?: number) {
    super(message);
    this.name = 'OpenFdaError';
    this.status = status;
  }
}

interface NdcRecord {
  product_ndc?: string;
  brand_name?: string;
  labeler_name?: string;
  dosage_form?: string;
  active_ingredients?: Array<{ name?: string; strength?: string }>;
}

/**
 * Strips everything openFDA's query grammar treats as structure.
 *
 * Quotes, colons, parentheses and boolean keywords are removed rather than
 * escaped. Escaping would preserve the user's characters and rely on getting
 * the rules exactly right; removing them means the worst a crafted query can do
 * is match nothing. The nicotine clause is not built from this string in any
 * case, but a search term that could close a quote would let a caller append
 * their own clause, and that is the one thing this function must not allow.
 */
function sanitise(term: string): string {
  return term
    .replace(/[^\p{L}\p{N}\s.-]/gu, ' ')
    .replace(/\b(AND|OR|NOT|TO)\b/gi, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

/**
 * Reads label milligrams out of an openFDA strength string.
 *
 * Values look like "4 mg/1" for a piece and "21 mg/24 h" for a patch — the
 * numerator is the dose and the denominator is the unit or the wear time, so
 * only the leading quantity is taken. Anything that does not start with a
 * number followed by mg returns null and costs the record its place in the
 * results, because a pad key showing the wrong dose is worse than one that
 * never appears. See `label-dose-is-not-delivered-dose` in the vault: this is
 * the number on the box, not what the body absorbs.
 */
function milligrams(strength: string | undefined): number | null {
  const match = /^\s*([\d.]+)\s*mg\b/i.exec(strength ?? '');
  if (!match) return null;
  const mg = Number(match[1]);
  return Number.isFinite(mg) && mg > 0 ? mg : null;
}

/** Maps an openFDA dosage form onto the allowlist, or null if it is not licensed NRT. */
function form(dosageForm: string | undefined) {
  const upper = (dosageForm ?? '').toUpperCase();
  return FORMS.find(([keyword]) => upper.includes(keyword))?.[1] ?? null;
}

/**
 * Keeps only records that are unambiguously a licensed nicotine product.
 *
 * The upstream query already constrains this, but the response is not trusted
 * to have honoured it: openFDA's relevance matching is fuzzy, and a filter that
 * exists only in a query string is one upstream change away from being no
 * filter at all.
 */
function toProduct(record: NdcRecord): NrtProduct | null {
  const ingredient = record.active_ingredients?.find((i) => /nicotine/i.test(i.name ?? ''));
  if (!ingredient) return null;

  const mapped = form(record.dosage_form);
  if (!mapped) return null;

  const mg = milligrams(ingredient.strength);
  if (mg === null) return null;

  const id = record.product_ndc?.trim();
  const brand = record.brand_name?.trim();
  if (!id || !brand) return null;

  return { id, brand, labeler: record.labeler_name?.trim() ?? '', form: mapped, mg };
}

/**
 * Searches licensed NRT by brand name.
 *
 * The nicotine clause is a constant joined to the sanitised term, never
 * assembled from it, so there is no input that produces a query without it.
 * That is deliberate: this function is the only route the app has to a product
 * catalogue, and it must not be capable of returning a tobacco product.
 */
export async function searchNrt(term: string, limit: number): Promise<NrtProduct[]> {
  const cleaned = sanitise(term);
  const clauses = ['active_ingredients.name:"nicotine"'];
  if (cleaned) clauses.push(`brand_name:"${cleaned}"`);

  const url = new URL(BASE);
  url.searchParams.set('search', clauses.join(' AND '));
  // Over-fetch, because the allowlist drops rows after the fact and a limit
  // applied upstream would otherwise silently shorten the result set.
  url.searchParams.set('limit', String(Math.min(limit * 4, 100)));
  const key = Deno.env.get('OPENFDA_API_KEY')?.trim();
  if (key) url.searchParams.set('api_key', key);

  let res: Response;
  try {
    res = await fetch(url, { headers: { Accept: 'application/json' } });
  } catch (err) {
    throw new OpenFdaError(`openFDA unreachable: ${err instanceof Error ? err.message : err}`);
  }

  // openFDA answers an empty result set with 404 rather than an empty array.
  // That is a legitimate "nothing by that name", which is what L3c shows, and
  // reporting it as an outage would send the user looking for a fault.
  if (res.status === 404) return [];
  if (!res.ok) throw new OpenFdaError(`openFDA returned ${res.status}`, res.status);

  const body = (await res.json()) as { results?: NdcRecord[] };
  const products: NrtProduct[] = [];
  for (const record of body.results ?? []) {
    const product = toProduct(record);
    if (product) products.push(product);
    if (products.length === limit) break;
  }
  return products;
}
