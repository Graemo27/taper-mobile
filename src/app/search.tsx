/**
 * Search — the bar, for now.
 *
 * The field is real: it takes typing, holds a value, and Cancel returns to the
 * Journal. What it does not do yet is look anything up. The lookup and the
 * results card land next, and the designed failure states after that.
 *
 * Splitting there rather than shipping a half-wired fetch keeps this reviewable:
 * everything here is on screen and exercisable, with nothing waiting on a caller
 * that does not exist.
 */

import { router } from 'expo-router';
import { useState } from 'react';
import { StyleSheet } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { SearchField } from '@/components/search-field';
import { colors } from '@/theme';

export default function Search() {
  const [query, setQuery] = useState('');

  return (
    <SafeAreaView style={styles.screen} edges={['top', 'bottom']}>
      <SearchField value={query} onChangeText={setQuery} onCancel={() => router.back()} />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.background },
});
