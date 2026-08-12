/**
 * One day of the journal: a heading, and a card of what was eaten.
 *
 * The same card as the search results — one surface, hairline-separated rows,
 * dividers between items rather than under each. The rows are not pressable:
 * an entry is a snapshot, not a link back to the food, so opening one would
 * show a detail screen that cannot be re-scaled without contradicting what was
 * saved.
 */

import { StyleSheet, Text, View } from 'react-native';

import type { JournalEntry } from '@/lib/supabase/journal';
import { colors, elevation, fontFamily, fontSize, letterSpacing, radius, spacing, tracking } from '@/theme';

function EntryRow({ entry }: { entry: JournalEntry }) {
  const kcal = entry.kcal === null ? null : `${entry.kcal} kcal`;

  return (
    <View
      style={styles.row}
      // Groups the row into one announcement on iOS and Android. On web it does
      // not — RN Web emits `aria-label` on a div with no role, which browsers
      // ignore, so the three texts are read in order there instead. Checked in
      // the a11y tree; left as is because the phones are the target and reading
      // name, then amount, then energy is a fair fallback.
      accessible
      accessibilityLabel={[entry.name, entry.servingLabel, kcal].filter(Boolean).join(', ')}
    >
      <View style={styles.text}>
        <Text style={styles.name} numberOfLines={1}>
          {entry.name}
        </Text>
        {/* Absent only for a row written before the label was stored. */}
        {entry.servingLabel && (
          <Text style={styles.serving} numberOfLines={1}>
            {entry.servingLabel}
          </Text>
        )}
      </View>

      {/* Fixed width even when empty, so the kcal column holds its lane down
          the card rather than shifting per row. */}
      <View style={styles.energy}>{kcal && <Text style={styles.energyText}>{kcal}</Text>}</View>
    </View>
  );
}

interface JournalDayProps {
  heading: string;
  count: string;
  entries: JournalEntry[];
  /** A day following another gets the design's extra 14pt above its heading. */
  after?: boolean;
}

export function JournalDay({ heading, count, entries, after = false }: JournalDayProps) {
  return (
    <View style={styles.day}>
      <View style={[styles.headingRow, after && styles.headingRowAfter]}>
        <Text style={styles.heading}>{heading}</Text>
        <Text style={styles.count}>{count}</Text>
      </View>

      <View style={styles.card}>
        {entries.map((entry, index) => (
          <View key={entry.id}>
            {index > 0 && (
              <View style={styles.dividerInset}>
                <View style={styles.divider} />
              </View>
            )}
            <EntryRow entry={entry} />
          </View>
        ))}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  day: { gap: spacing['3'] },
  // Baseline rather than centre, so the heading and its count sit on one line
  // together at two different sizes.
  headingRow: { flexDirection: 'row', alignItems: 'baseline', gap: spacing['2.5'] },
  headingRowAfter: { paddingTop: spacing['3.5'] },
  heading: {
    fontFamily: fontFamily.semibold,
    fontSize: fontSize.lg,
    lineHeight: 22,
    letterSpacing: letterSpacing(fontSize.lg, tracking.tight),
    color: colors.textPrimary,
  },
  count: {
    fontFamily: fontFamily.normal,
    fontSize: fontSize.sm,
    lineHeight: 18,
    color: colors.textSecondary,
  },
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
  energy: { width: 70, alignItems: 'flex-end' },
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
