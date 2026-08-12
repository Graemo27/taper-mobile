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
import { useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { HighInCard } from '@/components/high-in-card';
import { BackChevronIcon } from '@/components/icons';
import { NutritionCard } from '@/components/nutrition-card';
import { MAX_SERVINGS, MIN_SERVINGS, ServingCard } from '@/components/serving-card';
import { highIn } from '@/lib/food/claims';
import { scaleTo } from '@/lib/food/parse';
import { selectedFood } from '@/lib/food/selection';
import { colors, fontFamily, fontSize, letterSpacing, spacing, tracking } from '@/theme';

const CAPTION =
  'USDA values, scaled from one standard serving. What you actually ate will vary — this is the shape of the thing, not a measurement.';

export default function FoodDetail() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const food = selectedFood(Number(id));
  const [servings, setServings] = useState(MIN_SERVINGS);

  // Scaled from per-100g rather than by multiplying `perServing`, so the
  // rounding happens once at the end instead of compounding per serving.
  const basisGrams = food?.portion?.grams ?? 100;
  const nutrients = food ? scaleTo(food.per100g, basisGrams * servings) : null;

  // Per 100g, not the displayed portion and not the stepped count. The chips
  // describe the food; how much of it you logged does not change what it is.
  const claims = food ? highIn(food.per100g) : [];

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
        // A cold load with nothing handed over. Naming the cause beats an empty
        // shell that looks like a food with no data in it.
        <View style={styles.content}>
          <Text style={styles.missing}>This food is no longer loaded.</Text>
          <Text style={styles.missingBody}>Search for it again to see its detail.</Text>
        </View>
      ) : (
        <ScrollView style={styles.scroll} contentContainerStyle={styles.content}>
          <View style={styles.heading}>
            <Text style={styles.name}>{food.name}</Text>
          </View>

          <ServingCard
            portion={food.portion}
            servings={servings}
            onChange={(next) =>
              setServings(Math.min(MAX_SERVINGS, Math.max(MIN_SERVINGS, next)))
            }
          />
          {/* Before the figures, as the board has it. */}
          <HighInCard nutrients={claims} />
          <NutritionCard nutrients={nutrients} />

          <View style={styles.captionWrap}>
            <Text style={styles.caption}>{CAPTION}</Text>
          </View>
        </ScrollView>
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
});
