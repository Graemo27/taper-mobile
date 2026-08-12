/**
 * The nutrients this food is high in, as chips.
 *
 * The card renders nothing when the list is empty. Plenty of foods are not high
 * in anything — asparagus clears no threshold at any serving — and the design
 * has no empty state for this section, so the honest move is to leave it out
 * rather than invent copy explaining an absence.
 */

import { StyleSheet, Text, View } from 'react-native';

import { colors, elevation, fontFamily, fontSize, radius, spacing } from '@/theme';

export function HighInCard({ nutrients }: { nutrients: string[] }) {
  if (nutrients.length === 0) return null;

  return (
    <View style={styles.card}>
      <Text style={styles.heading}>High in</Text>
      <View
        style={styles.chips}
        // One announcement for the set. Read chip by chip they are bare words
        // with no subject; read together they are the sentence the card makes.
        accessible
        accessibilityLabel={`High in ${nutrients.join(', ')}`}
      >
        {nutrients.map((nutrient) => (
          <View key={nutrient} style={styles.chip}>
            <Text style={styles.chipLabel}>{nutrient}</Text>
          </View>
        ))}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    gap: spacing['4'],
    padding: spacing['4'],
    backgroundColor: colors.surface,
    borderRadius: radius['3xl'],
    boxShadow: elevation.sm,
  },
  heading: {
    fontFamily: fontFamily.medium,
    fontSize: fontSize.xs,
    lineHeight: 16,
    color: colors.textSecondary,
  },
  /** Wraps, because five chips do not fit one line at 402pt. */
  chips: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing['2'] },
  chip: {
    paddingVertical: spacing['1.5'],
    paddingHorizontal: spacing['3'],
    backgroundColor: colors.brandSubtle,
    borderRadius: radius.full,
  },
  chipLabel: {
    fontFamily: fontFamily.medium,
    fontSize: fontSize.sm,
    lineHeight: 18,
    color: colors.brand,
  },
});
