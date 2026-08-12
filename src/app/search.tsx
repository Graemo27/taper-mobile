/**
 * Search — type a food, get servings.
 *
 * The lookup is expensive on the server side: FDC's search returns no portions,
 * so the proxy fans out to `/food/{id}` per row and a five-row answer costs six
 * upstream requests. That is why this debounces rather than searching per
 * keystroke, and why a stale reply is dropped instead of rendered.
 *
 * Five outcomes reach the reader: loading, results, no matches, and the two
 * failure shapes. Each is a designed board, and each is chosen here rather than
 * inside a component, so the whole state machine is legible in one place.
 */

import { router } from 'expo-router';
import { useEffect, useRef, useState } from 'react';
import { ScrollView, StyleSheet, Text } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { FoodList } from '@/components/food-list';
import { FoodListSkeleton } from '@/components/food-list-skeleton';
import { NoMatches } from '@/components/no-matches';
import { SearchFailure } from '@/components/search-failure';
import { SearchField } from '@/components/search-field';
import type { Food } from '@/lib/food/types';
import { FoodSearchError, searchFoods } from '@/lib/supabase/food-search';
import { colors, fontFamily, fontSize, spacing } from '@/theme';

/** Long enough that "a" doesn't cost six upstream requests. */
const MIN_QUERY = 2;
const DEBOUNCE_MS = 400;

type Status = 'idle' | 'loading' | 'ready' | 'failed';

export default function Search() {
  const [query, setQuery] = useState('');
  const [status, setStatus] = useState<Status>('idle');
  const [foods, setFoods] = useState<Food[]>([]);
  const [failure, setFailure] = useState<FoodSearchError | null>(null);
  /** The query the current results or failure belong to, which is not `query`
   *  once the reader has carried on typing. The no-matches heading quotes it. */
  const [resolved, setResolved] = useState('');
  /** Bumped by Try again, so retrying re-runs the effect on an unchanged query. */
  const [attempt, setAttempt] = useState(0);

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
          setResolved(trimmed);
          setStatus('ready');
        })
        .catch((error: unknown) => {
          if (latest.current !== id) return;
          // Anything that is not a FoodSearchError is a bug on this side rather
          // than a reported failure, and gets the generic server-fault copy.
          setFailure(
            error instanceof FoodSearchError
              ? error
              : new FoodSearchError('Food lookup failed.', 'http'),
          );
          setResolved(trimmed);
          setStatus('failed');
        });
    }, DEBOUNCE_MS);

    return () => clearTimeout(timer);
  }, [query, attempt]);

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
        {status === 'loading' && (
          <>
            <Text style={styles.status}>Searching…</Text>
            <FoodListSkeleton />
          </>
        )}

        {status === 'ready' &&
          (foods.length > 0 ? (
            <>
              <Text style={styles.status}>
                {foods.length === 1 ? '1 match' : `${foods.length} matches`}
              </Text>
              <FoodList foods={foods} />
            </>
          ) : (
            <NoMatches query={resolved} onTryExample={setQuery} />
          ))}

        {status === 'failed' && failure && (
          <SearchFailure error={failure} onRetry={() => setAttempt((n) => n + 1)} />
        )}
      </ScrollView>
    </SafeAreaView>
  );
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
