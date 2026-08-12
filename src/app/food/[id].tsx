/**
 * Food detail — what one serving of this food is, and what is in it.
 *
 * The board carries five sections. Three are here: the name, the serving basis,
 * and the figures. "Rich in" needs nutrients the Edge Function does not yet
 * parse, and the processing scale needs a rule FDC has no field for — both are
 * their own PRs rather than a guess made here.
 *
 * The food itself is handed over by Search rather than fetched; see
 * `lib/food/selection.ts` for why, and for what that costs on a cold load.
 */

import { router, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { HighInCard } from '@/components/high-in-card';
import { BackChevronIcon, RetryIcon } from '@/components/icons';
import { NutritionCard } from '@/components/nutrition-card';
import { SaveFooter, type SaveState } from '@/components/save-footer';
import { MAX_SERVINGS, MIN_SERVINGS, ServingCard } from '@/components/serving-card';
import { highIn } from '@/lib/food/claims';
import { servingSummary } from '@/lib/food/format';
import { scaleTo } from '@/lib/food/parse';
import { fetchFood, FoodSearchError } from '@/lib/supabase/food-search';
import { toggleFavourite, useFavourites } from '@/lib/supabase/favourites';
import { saveEntry } from '@/lib/supabase/journal';
import { selectedFood } from '@/lib/food/selection';
import type { Food } from '@/lib/food/types';
import { colors, fontFamily, fontSize, letterSpacing, radius, spacing, tracking } from '@/theme';

const CAPTION =
  'USDA values, scaled from one standard serving. What you actually ate will vary — this is the shape of the thing, not a measurement.';

/**
 * Where the food came from. `held` covers both hand-off and a finished lookup —
 * by then they are the same object from the same source, and the screen has no
 * reason to render them differently.
 */
type Lookup = 'held' | 'looking' | 'missing' | 'failed';

export default function FoodDetail() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const fdcId = Number(id);

  // Handed over by Search when it is there, fetched when it is not — a reload,
  // or a link from outside the app. The hand-off is kept rather than replaced
  // by the fetch: Search has already resolved the whole food, and asking again
  // for what is in memory would put a round trip in front of every tap.
  const handed = selectedFood(fdcId);
  const [fetched, setFetched] = useState<Food | null>(null);
  const [lookup, setLookup] = useState<Lookup>(handed ? 'held' : 'looking');
  const food = handed ?? fetched;

  const looking = useRef(false);

  const look = useCallback(() => {
    if (looking.current) return;
    looking.current = true;
    setLookup('looking');

    fetchFood(fdcId)
      .then((result) => {
        setFetched(result);
        setLookup('held');
      })
      // A food FDC will not serve is an answer, not an outage, and Try again
      // would ask the same question forever. The two states differ by what
      // they offer, so they are told apart here rather than in the render.
      .catch((error) =>
        setLookup(error instanceof FoodSearchError && error.status === 404 ? 'missing' : 'failed'),
      )
      .finally(() => {
        looking.current = false;
      });
  }, [fdcId]);

  useEffect(() => {
    if (!handed && !fetched) look();
  }, [handed, fetched, look]);

  const [servings, setServings] = useState(MIN_SERVINGS);

  // Scaled from per-100g rather than by multiplying `perServing`, so the
  // rounding happens once at the end instead of compounding per serving.
  const basisGrams = food?.portion?.grams ?? 100;
  const nutrients = food ? scaleTo(food.per100g, basisGrams * servings) : null;

  // Per 100g, not the displayed portion and not the stepped count. The chips
  // describe the food; how much of it you logged does not change what it is.
  const claims = food ? highIn(food.per100g) : [];

  const [saveState, setSaveState] = useState<SaveState>('idle');

  // Shared with the results list, so a star set here is already showing when
  // you go back. Reading the store is what fills it.
  const favourites = useFavourites();

  // "Saved" is a confirmation, not a resting state — a second helping is a real
  // thing to log, so the button goes back to offering that.
  useEffect(() => {
    if (saveState !== 'saved') return;
    const timer = setTimeout(() => setSaveState('idle'), 2400);
    return () => clearTimeout(timer);
  }, [saveState]);

  async function save() {
    if (!food || !nutrients) return;

    setSaveState('saving');
    try {
      await saveEntry({
        food,
        servings,
        nutrients,
        // What the reader is looking at, stored as they saw it.
        servingLabel: food.portion
          ? servingSummary(food.portion, servings)
          : `${100 * servings} g`,
        grams: basisGrams * servings,
      });
      setSaveState('saved');
    } catch {
      // The wording belongs to the footer. Anything thrown here means the entry
      // did not land, which is all this needs to know.
      setSaveState('failed');
    }
  }

  return (
    <SafeAreaView style={styles.screen} edges={['top', 'bottom']}>
      <View style={styles.nav}>
        <Pressable
          // A cold load has no history, so `back()` alone is a dead control —
          // measured, not assumed: the button left the URL unchanged. Falling
          // through to Search makes the label true however the screen was
          // reached.
          onPress={() => (router.canGoBack() ? router.back() : router.replace('/search'))}
          style={({ pressed }) => [styles.back, pressed && styles.pressed]}
          accessibilityRole="button"
          accessibilityLabel="Back to search"
          // The label and chevron are a small target on their own.
          hitSlop={{ top: 12, bottom: 12, left: 16, right: 16 }}
        >
          <BackChevronIcon />
          <Text style={styles.backLabel}>Search</Text>
        </Pressable>
      </View>

      {food === null || nutrients === null ? (
        // Nothing to render yet, which is now three different situations. Each
        // says which one it is, rather than one shell that could mean any.
        <View style={styles.content}>
          {lookup === 'looking' && <Text style={styles.missing}>Looking up this food…</Text>}

          {lookup === 'missing' && (
            <>
              <Text style={styles.missing}>That food could not be found.</Text>
              <Text style={styles.missingBody}>
                USDA no longer serves it. Search for something else to log instead.
              </Text>
            </>
          )}

          {lookup === 'failed' && (
            <>
              <Text style={styles.missing}>Could not open this food.</Text>
              <Text style={styles.missingBody}>Nothing is wrong with your entry. Try again.</Text>

              <Pressable
                onPress={look}
                style={({ pressed }) => [styles.retry, pressed && styles.pressed]}
                accessibilityRole="button"
                accessibilityLabel="Try opening this food again"
              >
                <RetryIcon />
                <Text style={styles.retryLabel}>Try again</Text>
              </Pressable>
            </>
          )}
        </View>
      ) : (
        <ScrollView style={styles.scroll} contentContainerStyle={styles.content}>
          <View style={styles.heading}>
            <Text style={styles.name}>{food.name}</Text>
          </View>

          <ServingCard
            portion={food.portion}
            servings={servings}
            disabled={saveState === 'saving'}
            onChange={(next) => {
              setServings(Math.min(MAX_SERVINGS, Math.max(MIN_SERVINGS, next)));
              // A confirmation belongs to the amount that was saved. Once the
              // count moves it is describing something that never happened, so
              // it goes rather than sitting there next to a different number.
              setSaveState('idle');
            }}
          />
          {/* Before the figures, as the board has it. */}
          <HighInCard nutrients={claims} />
          <NutritionCard nutrients={nutrients} />

          <View style={styles.captionWrap}>
            <Text style={styles.caption}>{CAPTION}</Text>
          </View>
        </ScrollView>
      )}

      {/* Outside the ScrollView, as the board has it — the save stays reachable
          without scrolling back down to find it. */}
      {food !== null && nutrients !== null && (
        <SaveFooter
          state={saveState}
          onSave={save}
          favourite={favourites.has(food.fdcId)}
          onToggleFavourite={() => void toggleFavourite(food.fdcId)}
        />
      )}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.background },
  nav: { paddingTop: spacing['1.5'], paddingHorizontal: spacing['4'] },
  back: { flexDirection: 'row', alignItems: 'center', gap: spacing['1.5'], alignSelf: 'flex-start' },
  pressed: { opacity: 0.6 },
  backLabel: {
    fontFamily: fontFamily.medium,
    fontSize: fontSize.base,
    lineHeight: 20,
    color: colors.brand,
  },
  scroll: { flex: 1 },
  content: {
    paddingTop: spacing['4'],
    paddingHorizontal: spacing['4'],
    paddingBottom: spacing['8'],
    gap: spacing['2.5'],
  },
  heading: { paddingBottom: spacing['3.5'], gap: spacing['0.5'] },
  name: {
    fontFamily: fontFamily.semibold,
    fontSize: fontSize['3xl'],
    lineHeight: 36,
    letterSpacing: letterSpacing(fontSize['3xl'], tracking.tight),
    color: colors.textPrimary,
  },
  // The caption sits outside the cards, so it keeps its own inset rather than
  // inheriting the card padding.
  captionWrap: { paddingTop: spacing['1'] },
  caption: {
    fontFamily: fontFamily.normal,
    fontSize: fontSize.xs,
    lineHeight: 16,
    color: colors.textSecondary,
  },
  missing: {
    fontFamily: fontFamily.semibold,
    fontSize: fontSize.lg,
    lineHeight: 24,
    letterSpacing: letterSpacing(fontSize.lg, tracking.tight),
    color: colors.textPrimary,
  },
  missingBody: {
    fontFamily: fontFamily.normal,
    fontSize: fontSize.sm,
    lineHeight: 20,
    color: colors.textSecondary,
  },
  // The Journal's retry, to the pixel — the same control doing the same job on
  // a second screen should not be a second shape.
  retry: {
    flexDirection: 'row',
    alignItems: 'center',
    alignSelf: 'flex-start',
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
});
