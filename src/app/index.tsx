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
import { useCallback, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { RetryIcon } from '@/components/icons';
import { JournalDay } from '@/components/journal-day';
import { PlusIcon } from '@/components/plus-icon';
import { byDay, dayHeading, localDate, thingCount } from '@/lib/journal/days';
import { listEntries, type JournalEntry } from '@/lib/supabase/journal';
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
  /** Bumped by Try again, so a retry re-runs the read without a navigation. */
  const [attempt, setAttempt] = useState(0);

  const load = useCallback(() => {
    // A reply that arrives after the screen has been left belongs to a screen
    // that is no longer listening, so it is dropped rather than set.
    let listening = true;

    listEntries()
      .then((rows) => {
        if (!listening) return;
        setEntries(rows);
        setStatus('ready');
      })
      .catch(() => {
        if (!listening) return;
        setStatus('failed');
      });

    return () => {
      listening = false;
    };
  }, [attempt]);

  useFocusEffect(load);

  // Read once per render rather than per day, so a list rendering across
  // midnight cannot label two different dates Today.
  const today = localDate(new Date());
  const days = byDay(entries);

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
          />
        ))}

        {/* Both of these speak only when the list is genuinely empty. With rows
            on screen, a failed refresh must not replace a day someone can still
            read with an apology about it. */}
        {days.length === 0 && status === 'ready' && (
          <View style={styles.block}>
            <Text style={styles.blockHeading}>Nothing written down yet</Text>
            <Text style={styles.blockBody}>
              Add the first thing you ate and it will appear here, under today.
            </Text>
          </View>
        )}

        {days.length === 0 && status === 'failed' && (
          <View style={styles.block}>
            <Text style={styles.blockHeading}>Could not open your journal</Text>
            {/* Names no cause: a refused read, a missing table and a dropped
                connection all arrive here, and only one of them is a
                connection. What to do about it is the same either way. */}
            <Text style={styles.blockBody}>Your entries are still saved. Try again in a moment.</Text>

            <Pressable
              onPress={() => {
                setStatus('loading');
                setAttempt((n) => n + 1);
              }}
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
