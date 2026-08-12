/**
 * The failure state — four messages across one layout.
 *
 * Per the design note: only the heading and body change. The icon and the Try
 * again button stay put, and the reference line appears only when a response
 * came back carrying one.
 *
 * The copy is chosen here from the error's shape rather than rendered from
 * `error.message`. The function's own text is written to be safe to show, but
 * it is one sentence per case; these four are the designed copy, and keying
 * them off `kind`/`status` means the wording cannot drift when the server's
 * does. `FoodSearchFailure` has exactly these four outcomes, so there is no
 * case left over.
 */

import { Pressable, StyleSheet, Text, View } from 'react-native';

import { AlertIcon, RetryIcon } from '@/components/icons';
import type { FoodSearchError } from '@/lib/supabase/food-search';
import {
  colors,
  fontFamily,
  fontSize,
  letterSpacing,
  radius,
  spacing,
  tracking,
} from '@/theme';

interface Message {
  heading: string;
  body: string;
}

function messageFor(error: FoodSearchError): Message {
  if (error.kind === 'timeout') {
    return {
      heading: 'Food search took too long',
      body: "It didn't come back in time. A search usually takes a couple of seconds — worth another try. No reference code — no response came back to carry one.",
    };
  }

  if (error.kind === 'offline') {
    return {
      heading: "Can't reach food search",
      body: 'Check your connection, then try again. No reference code — the request never arrived.',
    };
  }

  if (error.status === 429) {
    return {
      heading: 'Too many lookups right now',
      body: 'Give it a minute and try again. Nothing you did — the food database limits how often we can ask.',
    };
  }

  return {
    heading: 'Food lookup is unavailable',
    body: 'This one is on our side, not yours. Your search is still here — try again in a moment.',
  };
}

interface SearchFailureProps {
  error: FoodSearchError;
  onRetry: () => void;
}

export function SearchFailure({ error, onRetry }: SearchFailureProps) {
  const { heading, body } = messageFor(error);

  return (
    <View style={styles.block}>
      <AlertIcon />

      <View style={styles.headingWrap}>
        <Text style={styles.heading}>{heading}</Text>
      </View>
      <Text style={styles.body}>{body}</Text>

      <Pressable
        onPress={onRetry}
        style={({ pressed }) => [styles.retry, pressed && styles.retryPressed]}
        accessibilityRole="button"
        accessibilityLabel="Try the search again"
      >
        <RetryIcon />
        <Text style={styles.retryLabel}>Try again</Text>
      </Pressable>

      {/* Only when the server assigned one. A timeout and an offline failure
          never reach a server that could, which is what their copy says. */}
      {error.requestId && <Text style={styles.reference}>Reference {error.requestId}</Text>}
    </View>
  );
}

const styles = StyleSheet.create({
  block: {
    alignItems: 'flex-start',
    gap: spacing['2'],
    paddingTop: spacing['6'],
    // Holds the body to a comfortable measure rather than the full width.
    paddingRight: spacing['6'],
  },
  headingWrap: { paddingTop: spacing['1'] },
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
  retry: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing['2'],
    marginTop: spacing['2'],
    paddingVertical: spacing['3'],
    paddingHorizontal: spacing['5'],
    borderRadius: radius.full,
    backgroundColor: colors.brand,
  },
  retryPressed: { opacity: 0.9 },
  retryLabel: {
    fontFamily: fontFamily.medium,
    fontSize: fontSize.sm,
    lineHeight: 18,
    color: colors.onBrand,
  },
  reference: {
    marginTop: spacing['3'],
    fontFamily: fontFamily.normal,
    fontSize: fontSize.xs,
    lineHeight: 16,
    color: colors.textSecondary,
  },
});
