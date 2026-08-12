/**
 * Journal — the home screen.
 *
 * A shell for now: the chrome and the one action, with no entries. The store
 * that would fill it does not exist yet, and neither does a designed empty
 * state, so the content area is deliberately blank rather than filled with
 * invented copy.
 *
 * What is here is what the design settles: no daily total, no goal, no streak.
 * The research this product follows found that feedback which evaluates rather
 * than informs gets people to stop recording, so there is deliberately nothing
 * here to be measured against.
 */

import { router } from 'expo-router';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { PlusIcon } from '@/components/plus-icon';
import { colors, fontFamily, fontSize, radius, spacing } from '@/theme';

export default function Journal() {
  return (
    <SafeAreaView style={styles.screen} edges={['top', 'bottom']}>
      <View style={styles.content} />

      <View style={styles.footer}>
        <Pressable
          onPress={() => router.push('/search')}
          style={({ pressed }) => [styles.add, pressed && styles.addPressed]}
          accessibilityRole="button"
          // Says what happens, not what the control is — a screen reader
          // announces the role already.
          accessibilityLabel="Add something you ate"
        >
          <PlusIcon color={colors.onBrand} />
          <Text style={styles.addLabel}>Add something you ate</Text>
        </Pressable>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
    backgroundColor: colors.background,
  },
  content: {
    flexGrow: 1,
    flexBasis: 0,
    paddingTop: spacing['4'],
    paddingHorizontal: spacing['4'],
    gap: spacing['3'],
  },
  footer: {
    // The design's 32pt bottom padding sits above the home indicator, which
    // SafeAreaView already accounts for, so this is spacing rather than inset.
    paddingTop: spacing['3.5'],
    paddingBottom: spacing['8'],
    paddingHorizontal: spacing['4'],
  },
  add: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: spacing['2'],
    padding: spacing['4'],
    borderRadius: radius.full,
    backgroundColor: colors.brand,
  },
  addPressed: {
    opacity: 0.9,
  },
  addLabel: {
    fontFamily: fontFamily.semibold,
    fontSize: fontSize.base,
    lineHeight: 20,
    color: colors.onBrand,
  },
});
