/**
 * What one serving is, and how many of them — the basis every number on the
 * screen is scaled to.
 *
 * The count lives on the screen rather than in here, because the nutrition
 * figures scale with it too. This card reports presses; it does not own the
 * number it displays.
 */

import { Pressable, StyleSheet, Text, View } from 'react-native';

import { MinusIcon, PlusIcon } from '@/components/icons';
import { servingSummary } from '@/lib/food/format';
import type { Portion } from '@/lib/food/types';
import { colors, elevation, fontFamily, fontSize, radius, spacing } from '@/theme';

/**
 * One serving is the floor — zero servings of a food is not a thing you ate,
 * and the figures would all read 0. The ceiling is a guard against a held
 * press running the count somewhere silly; the design sets neither.
 */
export const MIN_SERVINGS = 1;
export const MAX_SERVINGS = 20;

interface ServingCardProps {
  portion: Portion | null;
  servings: number;
  onChange: (servings: number) => void;
}

export function ServingCard({ portion, servings, onChange }: ServingCardProps) {
  // FDC lists no household portion for a fair number of foods. The design
  // assumes one exists; saying "1 serving" when the figures are really per
  // 100 g would be a quiet lie, so the basis is named for what it is.
  const title = portion
    ? `${servings} ${servings === 1 ? 'serving' : 'servings'}`
    : `${100 * servings} g`;
  const detail = portion ? servingSummary(portion, servings) : 'No household serving listed';

  const atMin = servings <= MIN_SERVINGS;
  const atMax = servings >= MAX_SERVINGS;

  return (
    <View style={styles.card}>
      <View style={styles.text}>
        <Text style={styles.title}>{title}</Text>
        <Text style={styles.detail}>{detail}</Text>
      </View>

      <View style={styles.stepper}>
        <Pressable
          onPress={() => onChange(servings - 1)}
          disabled={atMin}
          style={({ pressed }) => [styles.minus, pressed && styles.pressed, atMin && styles.spent]}
          accessibilityRole="button"
          accessibilityLabel="One serving fewer"
          accessibilityState={{ disabled: atMin }}
        >
          <MinusIcon />
        </Pressable>

        <Pressable
          onPress={() => onChange(servings + 1)}
          disabled={atMax}
          style={({ pressed }) => [styles.plus, pressed && styles.pressed, atMax && styles.spent]}
          accessibilityRole="button"
          accessibilityLabel="One serving more"
          accessibilityState={{ disabled: atMax }}
        >
          <PlusIcon />
        </Pressable>
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
  stepper: { flexDirection: 'row', alignItems: 'center', gap: spacing['2'], flexShrink: 0 },
  minus: {
    width: 38,
    height: 38,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radius.full,
  },
  plus: {
    width: 38,
    height: 38,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.brand,
    borderRadius: radius.full,
  },
  pressed: { opacity: 0.7 },
  /** Dimmed rather than hidden — the control keeps its lane at either end. */
  spent: { opacity: 0.35 },
});
