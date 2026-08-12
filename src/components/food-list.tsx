/**
 * The results card — a white surface with hairline-separated rows.
 *
 * One card rather than a card per row, so the list reads as a single object.
 * Dividers are inset 16pt and never appear after the last row, which is why they
 * are rendered between items instead of as a bottom border on each.
 */

import { router } from 'expo-router';
import { Fragment } from 'react';
import { Keyboard, Pressable, StyleSheet, Text, View } from 'react-native';

import { ChevronIcon } from '@/components/icons';
import { servingSummary } from '@/lib/food/format';
import { selectFood } from '@/lib/food/selection';
import type { Food } from '@/lib/food/types';
import { colors, elevation, fontFamily, fontSize, radius, spacing } from '@/theme';

/**
 * Pressable as of Food detail, which the chevron has been promising since the
 * results card was built. The row hands the resolved food over before pushing,
 * because the route receives an id and the Edge Function has no fetch-by-id —
 * see `lib/food/selection.ts`.
 */
function FoodRow({ food }: { food: Food }) {
  const nutrients = food.perServing ?? food.per100g;
  const kcal = nutrients.kcal === null ? null : `${Math.round(nutrients.kcal)} kcal`;
  const serving = servingSummary(food.portion);

  return (
    <Pressable
      onPress={() => {
        // The field is autoFocused, and the router marks the screen behind it
        // aria-hidden on push — leaving focus inside a hidden subtree. Also
        // just correct on native: the keyboard should not survive the screen
        // it belongs to.
        Keyboard.dismiss();
        selectFood(food);
        router.push(`/food/${food.fdcId}`);
      }}
      style={({ pressed }) => [styles.row, pressed && styles.rowPressed]}
      accessibilityRole="button"
      // Read as one sentence rather than three fragments; the kcal is dropped
      // when FDC has no Energy value, which is common for Foundation foods.
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
    </Pressable>
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
  // The card clips, so a pressed row tints to its own edges.
  rowPressed: { backgroundColor: colors.background },
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
