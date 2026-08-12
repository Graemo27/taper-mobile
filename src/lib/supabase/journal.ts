/**
 * Writing to the journal.
 *
 * An entry records what was eaten, not what to look up later. The nutrients are
 * stored as they were shown, so a USDA revision cannot retroactively edit
 * someone's Tuesday, and the Journal can render without a network call.
 */

import type { Food, Nutrients } from '../food/types.ts';
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
 */
function today(): string {
  const now = new Date();
  const pad = (value: number) => String(value).padStart(2, '0');
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
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
