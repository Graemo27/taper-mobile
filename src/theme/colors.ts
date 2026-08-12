/**
 * Colour tokens, ported from the Paper file `Food_Pad`.
 *
 * Two layers, as in the design file: raw ramps, then semantic names that alias
 * them. Components use the semantic layer only — change a ramp and the whole app
 * follows. Full 50–950 ramps are kept even where only a step or two is used yet,
 * so there is a sanctioned value to reach for.
 *
 * Light only. The Paper design has no dark palette, and inventing one is real
 * design work rather than a port — which is why the root layout no longer wraps
 * the app in a ThemeProvider that would switch to one that does not exist.
 */

/**
 * Neutral, tinted green rather than a pure grey. Derived from `#F7F8F8`, which
 * is the app background — R below G=B, so hue sits at 180° next to emerald's
 * 163° and reads as related to the brand rather than accidentally cool.
 */
export const neutral = {
  50: '#FAFCFC',
  100: '#F7F8F8',
  200: '#EBEFEF',
  300: '#DBE1E1',
  400: '#A4ACAC',
  500: '#687373',
  600: '#4F5959',
  700: '#3B4444',
  800: '#232929',
  900: '#161B1B',
  950: '#0A0D0D',
} as const;

/** Brand. Tailwind emerald. */
export const emerald = {
  50: '#ECFDF5',
  100: '#D1FAE5',
  200: '#A7F3D0',
  300: '#6EE7B7',
  400: '#34D399',
  500: '#10B981',
  600: '#059669',
  700: '#047857',
  800: '#065F46',
  900: '#064E3B',
  950: '#022C22',
} as const;

export const red = {
  50: '#FEF2F2',
  100: '#FEE2E2',
  200: '#FECACA',
  300: '#FCA5A5',
  400: '#F87171',
  500: '#EF4444',
  600: '#DC2626',
  700: '#B91C1C',
  800: '#991B1B',
  900: '#7F1D1D',
  950: '#450A0A',
} as const;

export const amber = {
  50: '#FFFBEB',
  100: '#FEF3C7',
  200: '#FDE68A',
  300: '#FCD34D',
  400: '#FBBF24',
  500: '#F59E0B',
  600: '#D97706',
  700: '#B45309',
  800: '#92400E',
  900: '#78350F',
  950: '#451A03',
} as const;

export const green = {
  50: '#F0FDF4',
  100: '#DCFCE7',
  200: '#BBF7D0',
  300: '#86EFAC',
  400: '#4ADE80',
  500: '#22C55E',
  600: '#16A34A',
  700: '#15803D',
  800: '#166534',
  900: '#14532D',
  950: '#052E16',
} as const;

export const white = '#FFFFFF';
export const black = '#000000';

/**
 * Semantic layer — what components actually reference.
 *
 * Status colours are for *system feedback only*: a failed save, an offline
 * state, a sync error, a saved confirmation. They must never colour a food, a
 * nutrient, or the processing scale. Grading foods red-to-green is the pattern
 * this product is built against — removing that judgement is what took
 * omission from 45% to 0% in the research the design follows.
 */
export const colors = {
  background: neutral[100],
  surface: white,
  textPrimary: neutral[900],
  textSecondary: neutral[500],
  border: neutral[200],

  brand: emerald[700],
  brandSubtle: emerald[50],
  onBrand: white,

  error: red[700],
  errorSubtle: red[50],
  onError: white,

  warning: amber[700],
  warningSubtle: amber[50],
  onWarning: white,

  success: green[700],
  successSubtle: green[50],
  onSuccess: white,

  /**
   * The favourite star, and nothing else.
   *
   * Gold, and deliberately not one of the status colours above. It says "you
   * marked this", not "this food is a caution" — a bookmark someone set
   * themselves makes no claim about the food, which is what the rule is
   * protecting against. Its own token so the exception stays legible and
   * cannot quietly drift into meaning warning.
   *
   * `amber[400]` is the gold the existing ramps can offer. A truer gold leaf
   * (#FFD700) would mean a one-off primitive outside the Tailwind ramps every
   * other colour here comes from, which costs more than the half-step it buys.
   */
  favourite: amber[400],
} as const;

export type ColorToken = keyof typeof colors;
