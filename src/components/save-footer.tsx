/**
 * Save to today.
 *
 * The board pairs this with a star for favouriting. The star is not here: it
 * needs a store of its own, and a control that looks live and does nothing is
 * the dead affordance the results row carried until Food detail existed. It
 * arrives with the feature behind it.
 *
 * Confirmation happens in place rather than by navigating away. The Journal
 * does not render entries yet, so leaving for it on success would look exactly
 * like nothing having happened.
 */

import { Pressable, StyleSheet, Text, View } from 'react-native';

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
}

export function SaveFooter({ state, onSave }: SaveFooterProps) {
  // Saved is not disabled — a second helping is a real thing to log, and the
  // label returns to "Save to today" shortly after.
  const busy = state === 'saving';

  return (
    <View style={styles.footer}>
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

      {state === 'failed' && (
        <Text style={styles.error}>Your entry was not saved. Check your connection.</Text>
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
  button: {
    alignItems: 'center',
    justifyContent: 'center',
    padding: spacing['4'],
    backgroundColor: colors.brand,
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
