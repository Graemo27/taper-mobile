/**
 * Turning a flat list of entries into the days the Journal shows.
 *
 * Dates stay `YYYY-MM-DD` strings throughout. `new Date('2026-08-12')` parses
 * as UTC midnight, which is the 11th anywhere west of Greenwich — the entry
 * would be filed under the wrong heading for the reader who wrote it.
 */

import type { JournalEntry } from '../supabase/journal.ts';

/** A local calendar date as `YYYY-MM-DD`. `toISOString()` would be UTC. */
export function localDate(at: Date): string {
  const pad = (value: number) => String(value).padStart(2, '0');
  return `${at.getFullYear()}-${pad(at.getMonth() + 1)}-${pad(at.getDate())}`;
}

export interface JournalDay {
  /** `YYYY-MM-DD`, doubling as the list key — one section per date. */
  date: string;
  entries: JournalEntry[];
}

/**
 * Groups entries into days, preserving rather than re-sorting — the query
 * already returns newest day first, newest entry within the day.
 */
export function byDay(entries: JournalEntry[]): JournalDay[] {
  const days: JournalDay[] = [];
  const seen = new Map<string, JournalDay>();

  for (const entry of entries) {
    const day = seen.get(entry.eatenOn);
    if (day) {
      day.entries.push(entry);
      continue;
    }

    const created: JournalDay = { date: entry.eatenOn, entries: [entry] };
    seen.set(entry.eatenOn, created);
    days.push(created);
  }

  return days;
}

/**
 * Today, Yesterday, or the date written out. `today` is a parameter so the
 * boundary can be tested at a date rather than only at whatever day it is.
 */
export function dayHeading(date: string, today: string): string {
  if (date === today) return 'Today';
  if (date === dayBefore(today)) return 'Yesterday';

  // Written out rather than 12/08, which means opposite things either side of
  // the Atlantic.
  const at = fromParts(date);
  return at.toLocaleDateString(undefined, {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
    // Only when it is not the year we are in, where it would be noise.
    ...(date.slice(0, 4) === today.slice(0, 4) ? {} : { year: 'numeric' }),
  });
}

/** Local midnight on that date, rather than UTC midnight the day before. */
function fromParts(date: string): Date {
  const [year, month, day] = date.split('-').map(Number);
  return new Date(year, month - 1, day);
}

/**
 * Day 0 rather than subtracting 86,400,000: it rolls back over months and
 * years, and a daylight-saving day is 23 or 25 hours long, which epoch
 * arithmetic gets wrong twice a year.
 */
function dayBefore(date: string): string {
  const at = fromParts(date);
  at.setDate(at.getDate() - 1);
  return localDate(at);
}

/** "3 things" — a count, not a score. Nothing here is being totalled. */
export function thingCount(entries: number): string {
  return entries === 1 ? '1 thing' : `${entries} things`;
}
