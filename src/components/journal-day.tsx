/**
 * One day of the journal: a heading, and a card of what was eaten.
 *
 * The same card as the search results — one surface, hairline-separated rows,
 * dividers between items rather than under each. The rows are not pressable:
 * an entry is a snapshot, not a link back to the food, so opening one would
 * show a detail screen that cannot be re-scaled without contradicting what was
 * saved.
 *
 * They do swipe, which is the one thing a resting row can offer without
 * carrying a control for it. A delete button on every row would put a standing
 * invitation to undo next to every meal someone logged.
 */

import { Pressable, StyleSheet, Text, View } from 'react-native';
import Swipeable from 'react-native-gesture-handler/ReanimatedSwipeable';

import { TrashIcon } from '@/components/icons';
import type { JournalEntry } from '@/lib/supabase/journal';
import { colors, elevation, fontFamily, fontSize, letterSpacing, radius, spacing, tracking } from '@/theme';

/** Wide enough for the label under the icon, and to read as a panel not a chip. */
const ACTION_WIDTH = 88;

function EntryRow({ entry, onRemove }: { entry: JournalEntry; onRemove: () => void }) {
  const kcal = entry.kcal === null ? null : `${entry.kcal} kcal`;

  return (
    <Swipeable
      renderRightActions={() => (
        <Pressable
          onPress={onRemove}
          style={styles.action}
          accessibilityRole="button"
          // Names the food, because a screen reader reaches this button without
          // the row it belongs to necessarily being what was last read.
          accessibilityLabel={`Remove ${entry.name}`}
        >
          <TrashIcon />
          <Text style={styles.actionLabel}>Remove</Text>
        </Pressable>
      )}
      // Opens on a short pull rather than demanding the full width, and does not
      // fly open on a flick past it — the action is destructive, so reaching it
      // should be deliberate.
      rightThreshold={ACTION_WIDTH / 2}
      overshootRight={false}
      friction={1.6}
    >
      <View
        style={styles.row}
        // Groups the row into one announcement on iOS and Android. On web it does
        // not — RN Web emits `aria-label` on a div with no role, which browsers
        // ignore, so the three texts are read in order there instead. Checked in
        // the a11y tree; left as is because the phones are the target and reading
        // name, then amount, then energy is a fair fallback.
        accessible
        accessibilityLabel={[entry.name, entry.servingLabel, kcal].filter(Boolean).join(', ')}
        // A swipe is invisible to anyone not using one. The same removal is
        // offered here as an action, so the row is not a dead end on VoiceOver.
        accessibilityActions={[{ name: 'magicTap', label: 'Remove this entry' }]}
        onAccessibilityAction={onRemove}
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
    </Swipeable>
  );
}

interface JournalDayProps {
  heading: string;
  count: string;
  entries: JournalEntry[];
  /** A day following another gets the design's extra 14pt above its heading. */
  after?: boolean;
  onRemove: (entry: JournalEntry) => void;
}

export function JournalDay({ heading, count, entries, after = false, onRemove }: JournalDayProps) {
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
            <EntryRow entry={entry} onRemove={() => onRemove(entry)} />
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
    // Opaque, or the action panel shows through the row sliding over it.
    backgroundColor: colors.surface,
  },
  action: {
    width: ACTION_WIDTH,
    // Stretches to whatever the row is, which varies with a missing serving
    // line. A fixed height would leave a strip of card beside it.
    height: '100%',
    alignItems: 'center',
    justifyContent: 'center',
    gap: spacing['1'],
    backgroundColor: colors.error,
  },
  actionLabel: {
    fontFamily: fontFamily.medium,
    fontSize: fontSize.xs,
    lineHeight: 16,
    color: colors.onError,
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
