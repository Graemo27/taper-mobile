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

/**
 * Deletes one entry.
 *
 * The id is enough: the delete policy scopes it to the owner, so a request for
 * someone else's row matches nothing rather than removing it. Naming the user
 * here as well would read as the security boundary, which it is not.
 *
 * Nothing is returned. A delete that matches no row is not an error to a
 * reader — the row is gone either way, which is what they asked for.
 */
export async function removeEntry(id: number): Promise<void> {
  const userId = await ensureSession();

  const { error } = await supabase
    .from('journal_entries')
    .delete()
    .eq('id', id)
    // Redundant against RLS, but it lets the planner use the index rather than
    // scanning, the same reason the read names the user.
    .eq('user_id', userId);

  if (error) throw new JournalError('Could not remove that entry.');
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
 * A food worth offering again, as the entry recorded it.
 *
 * Not a `Food`: an entry stores what was on screen, not the nutrient table
 * behind it. The fdcId is what makes the row openable — Food detail fetches by
 * it — and is why the row carries an id at all.
 */
export interface RecentFood {
  fdcId: number;
  name: string;
  servingLabel: string | null;
  kcal: number | null;
}

/**
 * How many entries are read to find the recent foods.
 *
 * Postgres has DISTINCT ON for this and PostgREST does not expose it, so the
 * duplicates are dropped here instead. The number is the span this can see
 * back over: someone who ate the same three things for a fortnight has fewer
 * than three distinct foods in their last fifty entries, and gets what there is.
 */
const RECENT_SCAN = 50;

/** The last few distinct foods, newest first. */
export async function listRecentFoods(limit = 3): Promise<RecentFood[]> {
  const userId = await ensureSession();

  const { data, error } = await supabase
    .from('journal_entries')
    .select('fdc_id, name, serving_label, kcal')
    .eq('user_id', userId)
    .order('eaten_on', { ascending: false })
    .order('created_at', { ascending: false })
    .limit(RECENT_SCAN);

  if (error) throw new JournalError('Could not read your journal.');

  const seen = new Set<number>();
  const foods: RecentFood[] = [];

  for (const row of data ?? []) {
    const fdcId = row.fdc_id as number;
    // The newest entry for a food wins, which is the first one seen here. A
    // later helping may have been a different size, and the size shown should
    // be the one most recently chosen.
    if (seen.has(fdcId)) continue;
    seen.add(fdcId);

    foods.push({
      fdcId,
      name: row.name as string,
      servingLabel: row.serving_label as string | null,
      kcal: row.kcal as number | null,
    });

    if (foods.length === limit) break;
  }

  return foods;
}

/**
 * How far back the Journal reads: a window of days, not a count of rows.
 *
 * A row cap can land inside a day, and a half-fetched day is worse than a
 * missing one — the heading would still say "5 things" over three of them. A
 * date bound cannot: a day is either wholly in the window or wholly out.
 *
 * History past this is a reflection screen with its own design, not this list
 * silently growing.
 */
const WINDOW_DAYS = 30;

/**
 * The oldest day the Journal shows, in the reader's own timezone.
 *
 * `WINDOW_DAYS - 1` because the bound is inclusive and today is one of the
 * thirty. Subtracting the full thirty returns thirty-one dates, which is not
 * what the constant above says.
 */
function windowStart(): string {
  const at = new Date();
  at.setDate(at.getDate() - (WINDOW_DAYS - 1));
  return localDate(at);
}

/**
 * A backstop against an unbounded read, not the shape of the answer — thirty
 * days of eating is a couple of hundred rows. The server has its own ceiling
 * (`db-max-rows`) and the lower of the two wins, which is why nothing below
 * infers anything from this number.
 */
const READ_CAP = 2000;

/** Every entry in the window, newest day first and newest entry within it. */
export async function listEntries(): Promise<JournalEntry[]> {
  const userId = await ensureSession();

  // `count` is what makes truncation detectable: it is the number of rows that
  // matched, not the number sent back.
  const { data, error, count } = await supabase
    .from('journal_entries')
    .select('id, eaten_on, name, serving_label, kcal', { count: 'exact' })
    // RLS already restricts this to the owner. Naming the user anyway lets the
    // planner use the (user_id, eaten_on desc) index rather than filtering.
    .eq('user_id', userId)
    // Bounded at the old end only. `eaten_on` comes from the device clock, so a
    // phone set ahead writes a row dated tomorrow — and an upper bound would
    // hide it, permanently, with no history screen or delete to reach it by. A
    // day heading in front of Today at least says what happened; a saved entry
    // that never appears reads as the save having failed.
    .gte('eaten_on', windowStart())
    .order('eaten_on', { ascending: false })
    .order('created_at', { ascending: false })
    .limit(READ_CAP);

  if (error) throw new JournalError('Could not read your journal.');

  const rows = data ?? [];

  // The rows a cap drops are the oldest, so the oldest day that did arrive may
  // be a fraction of itself — and its heading would confidently count that
  // fraction. Dropping the day is the honest end to a truncated read: a day
  // missing from the bottom of a month reads as the window ending, which it is.
  //
  // Comparing against `count` rather than against READ_CAP because the cap that
  // actually applied may have been the server's. Unless every row that arrived
  // is one day, where dropping it would leave the reader with an empty journal
  // and no idea why — a possibly short count beats that.
  const oldest = rows.length > 0 ? rows[rows.length - 1].eaten_on : null;
  const partial = count !== null && count > rows.length;
  const whole = partial && rows.some((row) => row.eaten_on !== oldest)
    ? rows.filter((row) => row.eaten_on !== oldest)
    : rows;

  return whole.map((row) => ({
    id: row.id as number,
    eatenOn: row.eaten_on as string,
    name: row.name as string,
    servingLabel: row.serving_label as string | null,
    // `integer` comes back as a number; the null is an FDC gap, kept as one.
    kcal: row.kcal as number | null,
  }));
}
