/**
 * Reading and writing the journal.
 *
 * An entry records what was eaten, not what to look up later. The nutrients are
 * stored as they were shown, so a USDA revision cannot retroactively edit
 * someone's Tuesday, and the Journal renders from the row alone — no FDC call,
 * which is why the read here asks for nothing the screen does not draw.
 */

import type { Food, Nutrients } from '../food/types.ts';
import { localDate } from '../journal/days.ts';
import { supabase } from './client.ts';
import { ensureSession } from './session.ts';

export class JournalError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'JournalError';
  }
}

/**
 * Today, in the reader's own timezone.
 *
 * `toISOString()` would be UTC, which is a different day for most of the world
 * for part of every day — dinner in California would land on tomorrow's page.
 * Shared with the Journal, which decides what to call a date by comparing it to
 * this one; two definitions of "today" would file an entry under a heading the
 * screen then refuses to call Today.
 */
function today(): string {
  return localDate(new Date());
}

export interface JournalDraft {
  food: Food;
  servings: number;
  /** Already scaled to `servings` — the figures the reader is looking at. */
  nutrients: Nutrients;
  /** The serving line as rendered, e.g. "2 oz · 46 whole kernels · 57 g". */
  servingLabel: string;
  grams: number;
}

export async function saveEntry(draft: JournalDraft): Promise<void> {
  const userId = await ensureSession();

  const { error } = await supabase.from('journal_entries').insert({
    user_id: userId,
    eaten_on: today(),
    fdc_id: draft.food.fdcId,
    name: draft.food.name,
    serving_label: draft.servingLabel,
    servings: draft.servings,
    grams: draft.grams,
    kcal: draft.nutrients.kcal,
    protein_g: draft.nutrients.proteinG,
    fibre_g: draft.nutrients.fibreG,
  });

  // Postgres messages name columns and constraints, which is the wrong register
  // for a screen and tells a reader nothing they can act on.
  if (error) throw new JournalError('Could not save to your journal.');
}

export interface JournalEntry {
  id: number;
  /** `YYYY-MM-DD` in the reader's own timezone, as it was written. */
  eatenOn: string;
  name: string;
  servingLabel: string | null;
  kcal: number | null;
}

/**
 * A cap rather than paging: 200 rows is roughly two months of eating. History
 * worth paging through is a reflection screen with its own design, not this
 * list silently growing.
 */
const RECENT_LIMIT = 200;

/** Every recent entry, newest day first and newest entry within the day. */
export async function listEntries(): Promise<JournalEntry[]> {
  const userId = await ensureSession();

  const { data, error } = await supabase
    .from('journal_entries')
    .select('id, eaten_on, name, serving_label, kcal')
    // RLS already restricts this to the owner. Naming the user anyway lets the
    // planner use the (user_id, eaten_on desc) index rather than filtering.
    .eq('user_id', userId)
    .order('eaten_on', { ascending: false })
    .order('created_at', { ascending: false })
    .limit(RECENT_LIMIT);

  if (error) throw new JournalError('Could not read your journal.');

  return (data ?? []).map((row) => ({
    id: row.id as number,
    eatenOn: row.eaten_on as string,
    name: row.name as string,
    servingLabel: row.serving_label as string | null,
    // `integer` comes back as a number; the null is an FDC gap, kept as one.
    kcal: row.kcal as number | null,
  }));
}
