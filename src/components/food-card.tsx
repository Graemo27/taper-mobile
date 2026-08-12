/**
 * The white card of food rows, and the row itself.
 *
 * Two lists draw this now — search results and the recent foods on the empty
 * search screen — and the board draws them identically, down to the lane the
 * kcal sits in. They were the same object in the design before they were the
 * same component here.
 *
 * The row takes text rather than a `Food`, because the two callers hold
 * different things: search has resolved foods, and a recent food is a journal
 * row that records what was shown, not the nutrient table behind it.
 */

import { Fragment, type ReactNode } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { ChevronIcon, StarIcon } from '@/components/icons';
import { colors, elevation, fontFamily, fontSize, radius, spacing } from '@/theme';

/**
 * One card rather than a card per row, so the list reads as a single object.
 * Dividers are inset 16pt and never appear after the last row, which is why
 * they are rendered between children instead of as a border on each.
 */
export function FoodCard({ children }: { children: ReactNode[] }) {
  return (
    <View style={styles.card}>
      {children.map((child, index) => (
        <Fragment key={index}>
          {index > 0 && (
            <View style={styles.dividerInset}>
              <View style={styles.divider} />
            </View>
          )}
          {child}
        </Fragment>
      ))}
    </View>
  );
}

interface FoodCardRowProps {
  name: string;
  serving: string;
  /** Already formatted — "164 kcal" — or null where FDC has no Energy value. */
  kcal: string | null;
  favourite: boolean;
  onPress: () => void;
}

export function FoodCardRow({ name, serving, kcal, favourite, onPress }: FoodCardRowProps) {
  return (
    <Pressable
      onPress={onPress}
      style={({ pressed }) => [styles.row, pressed && styles.rowPressed]}
      accessibilityRole="button"
      // Read as one sentence rather than four fragments; the kcal is dropped
      // when FDC has no Energy value, which is common for Foundation foods.
      accessibilityLabel={[name, serving, kcal, favourite && 'favourite'].filter(Boolean).join(', ')}
    >
      <View style={styles.text}>
        <Text style={styles.name} numberOfLines={1}>
          {name}
        </Text>
        <Text style={styles.serving} numberOfLines={1}>
          {serving}
        </Text>
      </View>

      {/* Its own fixed slot, so the kcal lane does not shift by a star's width
          between a favourited row and its neighbour. */}
      <View style={styles.starSlot}>
        {favourite && <StarIcon size={13} color={colors.favourite} filled />}
      </View>

      {/* Fixed width even when empty, so kcal and chevrons hold their lanes. */}
      <View style={styles.energy}>{kcal && <Text style={styles.energyText}>{kcal}</Text>}</View>

      <ChevronIcon />
    </Pressable>
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
  starSlot: { width: 13, alignItems: 'center' },
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
