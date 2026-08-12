/**
 * The loading card — the results card with its text replaced by bars.
 *
 * Same surface, radius, row height and divider inset as `FoodList`, so the real
 * rows land where the bars were instead of the card resizing under the reader.
 *
 * Bar widths are the design's, and are deliberately uneven: three identical rows
 * read as a graphic, three uneven ones read as text that has not arrived yet.
 */

import { useEffect, useRef } from 'react';
import { Animated, StyleSheet, View } from 'react-native';

import { colors, elevation, neutral, radius, spacing } from '@/theme';

/** [name, serving, energy] widths per row, from the Paper file. */
const ROWS: readonly (readonly [number, number, number])[] = [
  [172, 110, 44],
  [212, 88, 38],
  [146, 126, 48],
];

export function FoodListSkeleton() {
  const pulse = useRef(new Animated.Value(1)).current;

  useEffect(() => {
    const loop = Animated.loop(
      Animated.sequence([
        Animated.timing(pulse, { toValue: 0.55, duration: 700, useNativeDriver: true }),
        Animated.timing(pulse, { toValue: 1, duration: 700, useNativeDriver: true }),
      ]),
    );
    loop.start();
    return () => loop.stop();
  }, [pulse]);

  return (
    <Animated.View
      style={[styles.card, { opacity: pulse }]}
      // One announcement for the whole card. Eight separate bars would each be
      // an unlabelled node, and none of them mean anything on their own.
      accessibilityRole="progressbar"
      accessibilityLabel="Searching"
    >
      {ROWS.map(([name, serving, energy], index) => (
        <View key={index}>
          {index > 0 && (
            <View style={styles.dividerInset}>
              <View style={styles.divider} />
            </View>
          )}
          <View style={styles.row}>
            <View style={styles.text}>
              <View style={[styles.bar, styles.nameBar, { width: name }]} />
              <View style={[styles.bar, { width: serving, height: 8 }]} />
            </View>
            <View style={styles.energy}>
              <View style={[styles.bar, { width: energy }]} />
            </View>
            <View style={styles.chevron} />
          </View>
        </View>
      ))}
    </Animated.View>
  );
}

const styles = StyleSheet.create({
  card: {
    backgroundColor: colors.surface,
    borderRadius: radius['3xl'],
    boxShadow: elevation.sm,
    overflow: 'hidden',
  },
  // Fixed height rather than padding: there is no text here to set it, and the
  // real row's 14pt padding around two lines comes out at 68.
  row: {
    height: 68,
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing['3'],
    paddingHorizontal: spacing['4'],
  },
  text: { flex: 1, gap: spacing['2'] },
  bar: { height: 10, borderRadius: radius.full, backgroundColor: neutral[200] },
  nameBar: { backgroundColor: neutral[300] },
  energy: { width: 62, alignItems: 'flex-end' },
  /** Holds the chevron's lane so the bars sit where the real content will. */
  chevron: { width: 8 },
  dividerInset: { paddingHorizontal: spacing['4'] },
  divider: { height: 1, backgroundColor: colors.border },
});
