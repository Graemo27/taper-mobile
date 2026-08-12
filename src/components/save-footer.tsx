/**
 * Save to today, and the favourite star beside it.
 *
 * Confirmation happens in place rather than by navigating away. The Journal
 * does not render entries yet, so leaving for it on success would look exactly
 * like nothing having happened.
 */

import { Pressable, StyleSheet, Text, View } from 'react-native';

import { StarIcon } from '@/components/icons';
import { colors, elevation, fontFamily, fontSize, radius, spacing } from '@/theme';

export type SaveState = 'idle' | 'saving' | 'saved' | 'failed';

const LABEL: Record<SaveState, string> = {
  idle: 'Save to today',
  saving: 'Saving…',
  saved: 'Saved to today',
  failed: 'Try saving again',
};

interface SaveFooterProps {
  state: SaveState;
  onSave: () => void;
  favourite: boolean;
  onToggleFavourite: () => void;
}

export function SaveFooter({ state, onSave, favourite, onToggleFavourite }: SaveFooterProps) {
  // Saved is not disabled — a second helping is a real thing to log, and the
  // label returns to "Save to today" shortly after.
  const busy = state === 'saving';

  return (
    <View style={styles.footer}>
      <View style={styles.row}>
        <Pressable
          onPress={onSave}
          disabled={busy}
          style={({ pressed }) => [styles.button, pressed && styles.pressed]}
          accessibilityRole="button"
          accessibilityLabel={LABEL[state]}
          accessibilityState={{ disabled: busy, busy }}
        >
          <Text style={styles.label}>{LABEL[state]}</Text>
        </Pressable>

        <Pressable
          onPress={onToggleFavourite}
          style={({ pressed }) => [styles.star, pressed && styles.pressed]}
          accessibilityRole="button"
          accessibilityLabel={favourite ? 'Remove from favourites' : 'Add to favourites'}
          // A toggle, so the state is announced rather than left to the icon.
          accessibilityState={{ selected: favourite }}
        >
          <StarIcon filled={favourite} color={favourite ? colors.favourite : colors.textPrimary} />
        </Pressable>
      </View>

      {/* Names no cause, because this state cannot tell them apart. A missing
          table, an RLS refusal and a dropped connection all arrive here, and
          "check your connection" would be a confident wrong answer for two of
          the three. What the reader can act on is the same either way. */}
      {state === 'failed' && (
        <Text style={styles.error}>Your entry was not saved. Try again in a moment.</Text>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  footer: {
    gap: spacing['2'],
    paddingTop: spacing['3.5'],
    paddingBottom: spacing['8'],
    paddingHorizontal: spacing['4'],
  },
  row: { flexDirection: 'row', alignItems: 'center', gap: spacing['3'] },
  button: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: spacing['4'],
    backgroundColor: colors.brand,
    borderRadius: radius.full,
    boxShadow: elevation.sm,
  },
  star: {
    width: 54,
    height: 54,
    flexShrink: 0,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.surface,
    borderRadius: radius.full,
    boxShadow: elevation.sm,
  },
  pressed: { opacity: 0.9 },
  label: {
    fontFamily: fontFamily.semibold,
    fontSize: fontSize.base,
    lineHeight: 20,
    color: colors.onBrand,
  },
  error: {
    fontFamily: fontFamily.normal,
    fontSize: fontSize.sm,
    lineHeight: 18,
    color: colors.error,
    textAlign: 'center',
  },
});
