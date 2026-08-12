/**
 * The results card — a white surface with hairline-separated rows.
 *
 * One card rather than a card per row, so the list reads as a single object.
 * Dividers are inset 16pt and never appear after the last row, which is why they
 * are rendered between items instead of as a bottom border on each.
 */

import { Fragment } from 'react';
import { StyleSheet, Text, View } from 'react-native';

import { ChevronIcon } from '@/components/icons';
import type { Food, Portion } from '@/lib/food/types';
import { colors, elevation, fontFamily, fontSize, radius, spacing } from '@/theme';

/**
 * "1 oz (23 whole kernels)" + 28.35g → "1 oz · 23 whole kernels · 28 g".
 *
 * The design sets the serving as middle-dot segments, and FDC already supplies
 * the split — its labels carry the count in a parenthetical. So this is a
 * reformat of real data, not a rewrite of it: the words stay FDC's ("23 whole
 * kernels", not the design's shorter "23 nuts"), because shortening them would
 * mean a synonym table that has to be right about every food in the database.
 */
function servingSummary(portion: Portion | null): string {
  if (!portion) return '100 g';

  const match = /^(.*?)\s*\((.*)\)\s*$/.exec(portion.label);
  const parts = match ? [match[1], match[2]] : [portion.label];
  return [...parts, `${Math.round(portion.grams)} g`].join(' · ');
}

/**
 * Not pressable yet — the chevron is the design's, and Food detail is the next
 * screen. A `Pressable` with nowhere to go would either land on `+not-found` or
 * swallow the tap silently, so the row stays inert until the destination exists
 * rather than promising something it cannot do.
 */
function FoodRow({ food }: { food: Food }) {
  const nutrients = food.perServing ?? food.per100g;
  const kcal = nutrients.kcal === null ? null : `${Math.round(nutrients.kcal)} kcal`;
  const serving = servingSummary(food.portion);

  return (
    <View
      style={styles.row}
      // Read as one sentence rather than three fragments; the kcal is dropped
      // when FDC has no Energy value, which is common for Foundation foods.
      accessible
      accessibilityLabel={[food.name, serving, kcal].filter(Boolean).join(', ')}
    >
      <View style={styles.text}>
        <Text style={styles.name} numberOfLines={1}>
          {food.name}
        </Text>
        <Text style={styles.serving} numberOfLines={1}>
          {serving}
        </Text>
      </View>

      {/* Fixed width even when empty, so kcal and chevrons hold their lanes. */}
      <View style={styles.energy}>{kcal && <Text style={styles.energyText}>{kcal}</Text>}</View>

      <ChevronIcon />
    </View>
  );
}

export function FoodList({ foods }: { foods: Food[] }) {
  return (
    <View style={styles.card}>
      {foods.map((food, index) => (
        <Fragment key={food.fdcId}>
          {index > 0 && (
            <View style={styles.dividerInset}>
              <View style={styles.divider} />
            </View>
          )}
          <FoodRow food={food} />
        </Fragment>
      ))}
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    backgroundColor: colors.surface,
    borderRadius: radius['3xl'],
    boxShadow: elevation.sm,
    overflow: 'hidden',
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing['3'],
    paddingVertical: spacing['3.5'],
    paddingHorizontal: spacing['4'],
  },
  text: { flex: 1, gap: spacing['0.5'] },
  name: {
    fontFamily: fontFamily.medium,
    fontSize: fontSize.base,
    lineHeight: 20,
    color: colors.textPrimary,
  },
  serving: {
    fontFamily: fontFamily.normal,
    fontSize: fontSize.sm,
    lineHeight: 18,
    color: colors.textSecondary,
  },
  energy: { width: 62, alignItems: 'flex-end' },
  energyText: {
    fontFamily: fontFamily.medium,
    fontSize: fontSize.sm,
    lineHeight: 18,
    color: colors.textSecondary,
    textAlign: 'right',
  },
  dividerInset: { paddingHorizontal: spacing['4'] },
  divider: { height: 1, backgroundColor: colors.border },
});
