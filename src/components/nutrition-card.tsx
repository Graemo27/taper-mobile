/**
 * The three figures, in equal columns.
 *
 * Energy carries no unit in the number — the design puts "kcal" in the label
 * underneath — while protein and fibre carry their grams. A missing value shows
 * an em dash rather than a zero: FDC omits Energy on many Foundation foods, and
 * "0" would read as a claim about the food instead of a gap in the data.
 */

import { StyleSheet, Text, View } from 'react-native';

import { energy, grams } from '@/lib/food/format';
import type { Nutrients } from '../../supabase/functions/food-search/food/types.ts';
import { colors, elevation, fontFamily, fontSize, letterSpacing, radius, spacing, tracking } from '@/theme';

function Figure({ value, label }: { value: string; label: string }) {
  return (
    <View style={styles.figure}>
      <Text style={styles.value}>{value}</Text>
      <Text style={styles.label}>{label}</Text>
    </View>
  );
}

export function NutritionCard({ nutrients }: { nutrients: Nutrients }) {
  return (
    <View style={styles.card}>
      <Text style={styles.heading}>Nutrition</Text>
      <View style={styles.row}>
        <Figure value={energy(nutrients.kcal)} label="kcal" />
        <Figure value={grams(nutrients.proteinG)} label="protein" />
        <Figure value={grams(nutrients.fibreG)} label="fibre" />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    gap: spacing['3'],
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
  row: { flexDirection: 'row', alignItems: 'flex-start', gap: spacing['3'] },
  figure: { flex: 1, gap: spacing['0.5'] },
  value: {
    fontFamily: fontFamily.semibold,
    fontSize: fontSize['3xl'],
    lineHeight: 32,
    letterSpacing: letterSpacing(fontSize['3xl'], tracking.tight),
    color: colors.textPrimary,
  },
  label: {
    fontFamily: fontFamily.medium,
    fontSize: fontSize.base,
    lineHeight: 20,
    color: colors.textSecondary,
  },
});
