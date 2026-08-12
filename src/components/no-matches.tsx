/**
 * No results — the one failure that is not a failure.
 *
 * The copy names the actual cause rather than apologising: FDC's Foundation and
 * SR Legacy sets are whole ingredients, so a brand name finds nothing and will
 * keep finding nothing however many times it is retried. Saying so, and handing
 * over a working example to tap, is more use than "no results found".
 */

import { Pressable, StyleSheet, Text, View } from 'react-native';

import { SearchIcon } from '@/components/icons';
import {
  colors,
  fontFamily,
  fontSize,
  letterSpacing,
  radius,
  spacing,
  tracking,
} from '@/theme';

/**
 * Fixed, as in the design. It is an illustration of what a plain ingredient
 * looks like, not a guess at what this reader meant — deriving a real
 * suggestion from a failed query needs a search index we do not have, and a
 * wrong guess is worse than a clear example.
 */
const EXAMPLE = 'oats';

interface NoMatchesProps {
  query: string;
  onTryExample: (example: string) => void;
}

export function NoMatches({ query, onTryExample }: NoMatchesProps) {
  return (
    <View style={styles.block}>
      <Text style={styles.heading}>No matches for “{query}”</Text>
      <Text style={styles.body}>Food Pad looks up plain ingredients, not brands.</Text>

      <Pressable
        onPress={() => onTryExample(EXAMPLE)}
        style={({ pressed }) => [styles.chip, pressed && styles.chipPressed]}
        accessibilityRole="button"
        accessibilityLabel={`Search for ${EXAMPLE} instead`}
      >
        {/* Same magnifier as the field. At 15pt its stroke lands within a
            twentieth of a point of the design's lighter chip glyph, so it is
            the same icon rather than a near-duplicate to keep in step. */}
        <SearchIcon size={15} color={colors.brand} />
        <Text style={styles.chipLabel}>Try “{EXAMPLE}” instead</Text>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  block: {
    alignItems: 'flex-start',
    gap: spacing['2'],
    paddingTop: spacing['6'],
    paddingRight: spacing['6'],
  },
  heading: {
    fontFamily: fontFamily.semibold,
    fontSize: fontSize.lg,
    lineHeight: 24,
    letterSpacing: letterSpacing(fontSize.lg, tracking.tight),
    color: colors.textPrimary,
  },
  body: {
    fontFamily: fontFamily.normal,
    fontSize: fontSize.sm,
    lineHeight: 20,
    color: colors.textSecondary,
  },
  chip: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing['2'],
    marginTop: spacing['2'],
    paddingVertical: spacing['2.5'],
    paddingHorizontal: spacing['4'],
    borderRadius: radius.full,
    backgroundColor: colors.brandSubtle,
  },
  chipPressed: { opacity: 0.9 },
  chipLabel: {
    fontFamily: fontFamily.medium,
    fontSize: fontSize.sm,
    lineHeight: 18,
    color: colors.brand,
  },
});
