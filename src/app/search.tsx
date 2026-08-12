/**
 * Search — type a food, get servings.
 *
 * The lookup is expensive on the server side: FDC's search returns no portions,
 * so the proxy fans out to `/food/{id}` per row and a five-row answer costs six
 * upstream requests. That is why this debounces rather than searching per
 * keystroke, and why a stale reply is dropped instead of rendered.
 *
 * Failure states are deliberately plain here — the designed no-results, error
 * and timeout screens land next, and building them half-way now would mean
 * writing the copy twice.
 */

import { router } from 'expo-router';
import { useEffect, useRef, useState } from 'react';
import { ScrollView, StyleSheet, Text } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { FoodList } from '@/components/food-list';
import { FoodListSkeleton } from '@/components/food-list-skeleton';
import { SearchField } from '@/components/search-field';
import type { Food } from '@/lib/food/types';
import { searchFoods } from '@/lib/supabase/food-search';
import { colors, fontFamily, fontSize, spacing } from '@/theme';

/** Long enough that "a" doesn't cost six upstream requests. */
const MIN_QUERY = 2;
const DEBOUNCE_MS = 400;

type Status = 'idle' | 'loading' | 'ready' | 'failed';

export default function Search() {
  const [query, setQuery] = useState('');
  const [status, setStatus] = useState<Status>('idle');
  const [foods, setFoods] = useState<Food[]>([]);
  const [failure, setFailure] = useState('');

  // Monotonic id of the newest request. A reply whose id is not current lost a
  // race — the reader has typed on since — so it is discarded rather than shown.
  const latest = useRef(0);

  useEffect(() => {
    const trimmed = query.trim();
    if (trimmed.length < MIN_QUERY) {
      latest.current += 1;
      setStatus('idle');
      setFoods([]);
      return;
    }

    setStatus('loading');
    const id = (latest.current += 1);

    const timer = setTimeout(() => {
      searchFoods(trimmed)
        .then((result) => {
          if (latest.current !== id) return;
          setFoods(result.foods);
          setStatus('ready');
        })
        .catch((error: unknown) => {
          if (latest.current !== id) return;
          setFailure(error instanceof Error ? error.message : 'Food lookup failed.');
          setStatus('failed');
        });
    }, DEBOUNCE_MS);

    return () => clearTimeout(timer);
  }, [query]);

  return (
    <SafeAreaView style={styles.screen} edges={['top', 'bottom']}>
      <SearchField value={query} onChangeText={setQuery} onCancel={() => router.back()} />

      <ScrollView
        style={styles.results}
        contentContainerStyle={styles.resultsContent}
        // Without this the first tap only dismisses the keyboard, so choosing a
        // food from a list you are still typing into takes two taps.
        keyboardShouldPersistTaps="handled"
        keyboardDismissMode="on-drag"
      >
        {status !== 'idle' && <Text style={styles.status}>{statusLine(status, foods.length, failure)}</Text>}
        {status === 'loading' && <FoodListSkeleton />}
        {status === 'ready' && foods.length > 0 && <FoodList foods={foods} />}
      </ScrollView>
    </SafeAreaView>
  );
}

function statusLine(status: Status, count: number, failure: string): string {
  if (status === 'loading') return 'Searching…';
  if (status === 'failed') return failure;
  return count === 1 ? '1 match' : `${count} matches`;
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.background },
  results: { flex: 1 },
  resultsContent: {
    paddingTop: spacing['5'],
    paddingHorizontal: spacing['4'],
    paddingBottom: spacing['8'],
    gap: spacing['2.5'],
  },
  status: {
    fontFamily: fontFamily.normal,
    fontSize: fontSize.sm,
    lineHeight: 18,
    color: colors.textSecondary,
  },
});
