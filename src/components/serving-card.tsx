/**
 * What one serving is — the basis every number on the screen is scaled to.
 *
 * The design pairs this with a stepper that multiplies the serving count. The
 * stepper is the next PR, so the count is fixed at one here; the card is the
 * designed surface either way, and the line is not decoration — without it the
 * nutrition figures below are unlabelled quantities.
 */

import { StyleSheet, Text, View } from 'react-native';

import { servingSummary } from '@/lib/food/format';
import type { Portion } from '@/lib/food/types';
import { colors, elevation, fontFamily, fontSize, radius, spacing } from '@/theme';

export function ServingCard({ portion }: { portion: Portion | null }) {
  // FDC lists no household portion for a fair number of foods. The design
  // assumes one exists; saying "1 serving" when the figures are really per
  // 100 g would be a quiet lie, so the basis is named for what it is.
  const title = portion ? '1 serving' : '100 g';
  const detail = portion ? servingSummary(portion) : 'No household serving listed';

  return (
    <View style={styles.card}>
      <View style={styles.text}>
        <Text style={styles.title}>{title}</Text>
        <Text style={styles.detail}>{detail}</Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing['3'],
    paddingVertical: spacing['3.5'],
    paddingHorizontal: spacing['4'],
    backgroundColor: colors.surface,
    borderRadius: radius['3xl'],
    boxShadow: elevation.sm,
  },
  text: { flex: 1, gap: spacing['0.5'] },
  title: {
    fontFamily: fontFamily.semibold,
    fontSize: fontSize.lg,
    lineHeight: 22,
    color: colors.textPrimary,
  },
  detail: {
    fontFamily: fontFamily.normal,
    fontSize: fontSize.sm,
    lineHeight: 18,
    color: colors.textSecondary,
  },
});
