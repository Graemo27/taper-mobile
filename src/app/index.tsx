/**
 * Journal — the home screen, and now what is actually on it.
 *
 * Days newest first, each a heading and a card. What is deliberately absent is
 * what the design settles: no daily total, no goal, no streak. The research
 * this product follows found that feedback which evaluates rather than informs
 * gets people to stop recording, so there is nothing here to be measured
 * against — the count beside a heading says "3 things", not 631 kcal.
 *
 * The list reads on focus rather than on mount, because the way an entry
 * arrives is: leave here, save on Food detail, come back. Focus covers the cold
 * start too — one request, checked — and reloading keeps what is already on
 * screen until the answer lands, so returning from a save does not blink
 * through an empty state on the way to showing one more row.
 */

import { router, useFocusEffect } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { FoodListSkeleton } from '@/components/food-list-skeleton';
import { RetryIcon } from '@/components/icons';
import { JournalDay } from '@/components/journal-day';
import { PlusIcon } from '@/components/plus-icon';
import { byDay, dayHeading, localDate, thingCount } from '@/lib/journal/days';
import { listEntries, removeEntry, type JournalEntry } from '@/lib/supabase/journal';
import {
  colors,
  fontFamily,
  fontSize,
  letterSpacing,
  radius,
  spacing,
  tracking,
} from '@/theme';

type Status = 'loading' | 'ready' | 'failed';

export default function Journal() {
  const [status, setStatus] = useState<Status>('loading');
  const [entries, setEntries] = useState<JournalEntry[]>([]);

  /** The food whose removal failed, named so the message is about that row. */
  const [failedRemoval, setFailedRemoval] = useState<string | null>(null);

  /**
   * Entries removed here, which a read may not know about yet.
   *
   * A read issued before a delete still answers with the row it deleted, and
   * that answer can land afterwards — measured at a 2.9s gap between the 204
   * and the stale reply. Without this the row returns to the screen while the
   * database says it is gone, which is the one state neither the reader nor a
   * later read can explain. Ids leave the set only when a delete fails.
   */
  const removed = useRef(new Set<number>());

  // Returning to this screen runs the focus effect several times over — the
  // navigation state settles across renders and each one re-runs it. Measured
  // at five reads for one return, and the first attempt at guarding this with a
  // newest-request-wins id made it worse: each new read invalidated the reply of
  // the one before, so the screen sat loading after an answer had arrived.
  //
  // One read at a time instead. A focus that lands while one is in flight is
  // dropped rather than queued — it would be asking the same question — and a
  // focus after it finishes reads again as normal.
  const reading = useRef(false);

  const load = useCallback(() => {
    if (reading.current) return;
    reading.current = true;
    setStatus('loading');

    listEntries()
      .then((rows) => {
        setEntries(rows.filter((row) => !removed.current.has(row.id)));
        setStatus('ready');
      })
      .catch(() => setStatus('failed'))
      .finally(() => {
        reading.current = false;
      });
  }, []);

  useFocusEffect(load);

  const [today, setToday] = useState(localDate);
  const days = byDay(entries);

  // Midnight has to be waited for, not noticed on the next render. A screen
  // left open past it would otherwise go on calling yesterday Today — the one
  // heading here that must never be wrong. Re-armed each day, one second past
  // the boundary so a fast clock cannot land on the old date.
  useEffect(() => {
    const now = new Date();
    const midnight = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 0, 0, 1);
    const timer = setTimeout(() => setToday(localDate()), midnight.getTime() - now.getTime());
    return () => clearTimeout(timer);
  }, [today]);

  /**
   * Optimistic, like the favourite star: the row goes at once and comes back if
   * the delete fails. Waiting on a round trip to remove something you have
   * already decided about is the worse trade, and a reappearing row says what
   * happened more plainly than a spinner on a row you meant to be rid of.
   *
   * Restored by re-reading rather than by splicing the old row back in: the
   * position it held depends on the whole day, and the read is the thing that
   * knows.
   */
  function remove(entry: JournalEntry) {
    // A previous failure is about a row that is no longer what is happening.
    setFailedRemoval(null);
    removed.current.add(entry.id);
    setEntries((current) => current.filter((row) => row.id !== entry.id));

    void removeEntry(entry.id).catch(() => {
      // It is still there, so it is no longer something to filter out — and the
      // read below is what puts it back where it belongs.
      removed.current.delete(entry.id);
      setFailedRemoval(entry.name);
      load();
    });
  }

  return (
    <SafeAreaView style={styles.screen} edges={['top', 'bottom']}>
      <ScrollView style={styles.scroll} contentContainerStyle={styles.content}>
        {days.map((day, index) => (
          <JournalDay
            key={day.date}
            heading={dayHeading(day.date, today)}
            count={thingCount(day.entries.length)}
            entries={day.entries}
            after={index > 0}
            onRemove={remove}
          />
        ))}

        {/* The row came back on its own; this says why, and names which one so
            a reader who removed two things knows which of them stayed. */}
        {failedRemoval !== null && (
          <Text style={styles.removalFailed}>
            {failedRemoval} is still here — removing it did not go through.
          </Text>
        )}

        {/* Only before there is anything to look at. A refresh behind a list
            already on screen is not worth replacing that list with bars. */}
        {days.length === 0 && status === 'loading' && (
          <FoodListSkeleton label="Opening your journal" />
        )}

        {days.length === 0 && status === 'ready' && (
          <View style={styles.block}>
            <Text style={styles.blockHeading}>Nothing written down yet</Text>
            <Text style={styles.blockBody}>
              Add the first thing you ate and it will appear here, under today.
            </Text>
          </View>
        )}

        {/* Shown whether or not days are on screen: a refresh that failed
            behind a list leaves the reader looking at something they believe is
            current, and the entry they just saved missing from it. The days
            stay — the failure is reported beneath them rather than instead of
            them, and the wording says which of the two happened. */}
        {status === 'failed' && (
          <View style={styles.block}>
            <Text style={styles.blockHeading}>
              {days.length === 0 ? 'Could not open your journal' : 'Could not check for new entries'}
            </Text>
            {/* Names no cause: a refused read, a missing table and a dropped
                connection all arrive here, and only one of them is a
                connection. What to do about it is the same either way. */}
            <Text style={styles.blockBody}>
              {days.length === 0
                ? 'Your entries are still saved. Try again in a moment.'
                : 'This is what was here when it last read. Anything saved since may be missing.'}
            </Text>

            <Pressable
              onPress={load}
              style={({ pressed }) => [styles.retry, pressed && styles.pressed]}
              accessibilityRole="button"
              accessibilityLabel="Try opening your journal again"
            >
              <RetryIcon />
              <Text style={styles.retryLabel}>Try again</Text>
            </Pressable>
          </View>
        )}
      </ScrollView>

      <View style={styles.footer}>
        <Pressable
          onPress={() => router.push('/search')}
          style={({ pressed }) => [styles.add, pressed && styles.pressed]}
          accessibilityRole="button"
          // Says what happens, not what the control is — a screen reader
          // announces the role already.
          accessibilityLabel="Add something you ate"
        >
          <PlusIcon color={colors.onBrand} />
          <Text style={styles.addLabel}>Add something you ate</Text>
        </Pressable>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
    backgroundColor: colors.background,
  },
  scroll: { flex: 1 },
  content: {
    paddingTop: spacing['4'],
    paddingHorizontal: spacing['4'],
    paddingBottom: spacing['8'],
    // The design's 14pt above a following heading, on top of this 12pt gap.
    gap: spacing['3'],
  },
  block: {
    alignItems: 'flex-start',
    gap: spacing['2'],
    paddingTop: spacing['6'],
    // Holds the body to a comfortable measure rather than the full width.
    paddingRight: spacing['6'],
  },
  blockHeading: {
    fontFamily: fontFamily.semibold,
    fontSize: fontSize.lg,
    lineHeight: 24,
    letterSpacing: letterSpacing(fontSize.lg, tracking.tight),
    color: colors.textPrimary,
  },
  removalFailed: {
    fontFamily: fontFamily.normal,
    fontSize: fontSize.sm,
    lineHeight: 20,
    color: colors.error,
    paddingTop: spacing['1'],
  },
  blockBody: {
    fontFamily: fontFamily.normal,
    fontSize: fontSize.sm,
    lineHeight: 20,
    color: colors.textSecondary,
  },
  retry: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing['2'],
    marginTop: spacing['2'],
    paddingVertical: spacing['3'],
    paddingHorizontal: spacing['5'],
    borderRadius: radius.full,
    backgroundColor: colors.brand,
  },
  retryLabel: {
    fontFamily: fontFamily.medium,
    fontSize: fontSize.sm,
    lineHeight: 18,
    color: colors.onBrand,
  },
  footer: {
    // The design's 32pt bottom padding sits above the home indicator, which
    // SafeAreaView already accounts for, so this is spacing rather than inset.
    paddingTop: spacing['3.5'],
    paddingBottom: spacing['8'],
    paddingHorizontal: spacing['4'],
  },
  add: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: spacing['2'],
    padding: spacing['4'],
    borderRadius: radius.full,
    backgroundColor: colors.brand,
  },
  pressed: {
    opacity: 0.9,
  },
  addLabel: {
    fontFamily: fontFamily.semibold,
    fontSize: fontSize.base,
    lineHeight: 20,
    color: colors.onBrand,
  },
});
