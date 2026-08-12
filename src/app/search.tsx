/**
 * Search — a stub, so the Journal's one action leads somewhere real.
 *
 * The designed screen has five states (recent, loading, no results, error,
 * timeout) and lands in its own PR, replacing this wholesale. What is here is
 * the one part it cannot do without: a way back out. Cancel sits top-right in
 * the design, so this is the real affordance rather than invented chrome.
 */

import { router } from 'expo-router';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { colors, fontFamily, fontSize, spacing } from '@/theme';

export default function Search() {
  return (
    <SafeAreaView style={styles.screen} edges={['top', 'bottom']}>
      <View style={styles.bar}>
        <Pressable onPress={() => router.back()} accessibilityRole="button" hitSlop={8}>
          <Text style={styles.cancel}>Cancel</Text>
        </Pressable>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.background },
  bar: {
    flexDirection: 'row',
    justifyContent: 'flex-end',
    paddingHorizontal: spacing['4'],
    paddingVertical: spacing['3'],
  },
  cancel: { fontFamily: fontFamily.medium, fontSize: fontSize.base, lineHeight: 20, color: colors.brand },
});
