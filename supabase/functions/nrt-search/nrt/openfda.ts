/**
 * openFDA NDC directory lookup, restricted to licensed NRT.
 *
 * The NDC endpoint rather than the drug label one because it carries
 * `active_ingredients[].strength` as a field — a key needs a number, and parsing
 * "each piece contains 4 mg" out of label prose would be a guess dressed as
 * data.
 *
 * No API key is required. openFDA rate-limits anonymous callers by IP, which is
 * a further reason this runs server-side: one function's IP is a known quantity
 * to reason about when the limit bites, where every device having its own would
 * not be. The optional `OPENFDA_API_KEY` raises the ceiling and is never needed.
 */

import { FORMS, type NrtProduct } from './types.ts';

const BASE = 'https://api.fda.gov/drug/ndc.json';

/** Well inside any platform invocation limit, and long enough that a slow but working openFDA still answers. */
const TIMEOUT_MS = 5_000;

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
  active_ingredients?: { name?: string; strength?: string }[];
}

/**
 * Strips everything openFDA's query grammar treats as structure.
 *
 * Removed rather than escaped: escaping preserves the characters and relies on
 * getting openFDA's rules exactly right, where removal means the worst a crafted
 * query can do is match nothing. The nicotine clause is not built from this
 * string in any case, but a term able to close a quote could append its own,
 * and that is the one thing this module must not allow.
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
 * Values look like "4 mg/1" for a piece and "21 mg/24 h" for a patch, so only
 * the numerator is taken — the denominator is the unit or the wear time.
 * Anything unreadable returns null and costs the record its place, because a
 * key showing the wrong dose is worse than one that never appears. This is the
 * number on the box, not what the body absorbs; see
 * `label-dose-is-not-delivered-dose` in the vault.
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
 * Keeps only records that are unambiguously a licensed nicotine product. The
 * query already constrains this, but the response is not trusted to have
 * honoured it: openFDA's matching is fuzzy, and a filter living only in a query
 * string is one upstream change away from being no filter at all.
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
 * Searches licensed NRT by brand name. The nicotine clause is a constant joined
 * to the sanitised term, never assembled from it, so no input produces a query
 * without it — this is the app's only route to a product catalogue, and it must
 * not be capable of returning a tobacco product.
 */
export async function searchNrt(term: string, limit: number): Promise<NrtProduct[]> {
  // Clamped rather than trusted: the handler validates too, but this module is
  // exported and tested alone, and a fractional limit would never equal a row
  // count, leaving the loop to return every over-fetched row.
  const wanted = Math.min(Math.max(Math.trunc(limit) || 0, 1), 25);
  const cleaned = sanitise(term);
  const clauses = ['active_ingredients.name:"nicotine"'];
  if (cleaned) clauses.push(`brand_name:"${cleaned}"`);

  const url = new URL(BASE);
  url.searchParams.set('search', clauses.join(' AND '));
  // Over-fetch, because the allowlist drops rows after the fact and a limit
  // applied upstream would otherwise silently shorten the result set.
  url.searchParams.set('limit', String(Math.min(wanted * 4, 100)));
  const key = Deno.env.get('OPENFDA_API_KEY')?.trim();
  if (key) url.searchParams.set('api_key', key);

  let res: Response;
  try {
    // Bounded so a slow upstream cannot hold the invocation open until the
    // platform kills it. The catch below turns the abort into an OpenFdaError.
    res = await fetch(url, {
      headers: { Accept: 'application/json' },
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
  } catch {
    // Deliberately fixed, never `err.message`. Deno puts the full request URL
    // in a fetch TypeError, and the URL carries OPENFDA_API_KEY — interpolating
    // it would write the secret into whatever logs this.
    throw new OpenFdaError('openFDA unreachable');
  }

  // openFDA answers an empty result set with 404 rather than an empty array.
  // That is a legitimate "nothing by that name", which is what L3c shows, and
  // reporting it as an outage would send the user looking for a fault.
  if (res.status === 404) return [];
  if (!res.ok) throw new OpenFdaError(`openFDA returned ${res.status}`, res.status);

  let body: { results?: NdcRecord[] };
  try {
    body = (await res.json()) as { results?: NdcRecord[] };
  } catch {
    // A 200 carrying non-JSON is still an upstream fault; a bare SyntaxError
    // would escape as a 500 and read as our bug.
    throw new OpenFdaError('openFDA returned an unreadable body', res.status);
  }

  const products: NrtProduct[] = [];
  for (const record of body.results ?? []) {
    const product = toProduct(record);
    if (product) products.push(product);
    if (products.length >= wanted) break;
  }
  return products;
}
