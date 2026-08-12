/**
 * The search bar — field plus Cancel, as one unit.
 *
 * Every Search state in the design shows this identically, so it is the one part
 * that never re-renders differently. Cancel lives here rather than in the screen
 * for that reason: the two are a single row in the design file, and splitting
 * them would let the gap drift.
 *
 * The design draws a caret as a 2px brand bar. That is how a static tool shows a
 * focused field; here the field really is focused, so the platform draws it and
 * `selectionColor` gives it the brand colour instead.
 */

import { Pressable, StyleSheet, Text, TextInput, View } from 'react-native';

import { SearchIcon } from '@/components/icons';
import { colors, fontFamily, fontSize, radius, spacing } from '@/theme';

interface SearchFieldProps {
  value: string;
  onChangeText: (next: string) => void;
  onCancel: () => void;
}

export function SearchField({ value, onChangeText, onCancel }: SearchFieldProps) {
  return (
    <View style={styles.bar}>
      <View style={styles.field}>
        <SearchIcon />
        <TextInput
          value={value}
          onChangeText={onChangeText}
          style={styles.input}
          placeholder="Search a food"
          placeholderTextColor={colors.textSecondary}
          selectionColor={colors.brand}
          // The screen exists to be typed in, and arrives from a deliberate tap.
          autoFocus
          autoCorrect={false}
          autoCapitalize="none"
          returnKeyType="search"
          accessibilityLabel="Search for a food"
        />
      </View>

      <Pressable onPress={onCancel} accessibilityRole="button" hitSlop={8}>
        <Text style={styles.cancel}>Cancel</Text>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  bar: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing['3.5'],
    paddingHorizontal: spacing['4'],
    paddingTop: spacing['1.5'],
  },
  field: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing['2.5'],
    paddingVertical: spacing['3'],
    paddingHorizontal: spacing['4'],
    backgroundColor: colors.surface,
    borderWidth: 1.5,
    borderColor: colors.brand,
    borderRadius: radius.xl,
  },
  input: {
    flex: 1,
    fontFamily: fontFamily.normal,
    fontSize: fontSize.base,
    lineHeight: 20,
    color: colors.textPrimary,
    // RN gives TextInput its own vertical padding on Android; the field frame
    // above already owns that, so zero it out or the row grows past the design.
    paddingVertical: 0,
  },
  cancel: {
    fontFamily: fontFamily.medium,
    fontSize: fontSize.base,
    lineHeight: 20,
    color: colors.brand,
  },
});
