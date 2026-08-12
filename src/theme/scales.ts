/**
 * Dimensional tokens, ported from the Paper file `Food_Pad`.
 *
 * Tailwind v4 scales throughout, so names map 1:1 with the design file and with
 * any future web surface. Full scales are kept even where the app uses only a
 * few steps — the point is to have a sanctioned value to reach for rather than
 * inventing one at the call site.
 */

import type { BoxShadowValue } from 'react-native';

/** Tailwind numeric spacing. Key is the Tailwind step, value is points. */
export const spacing = {
  '0': 0,
  '0.5': 2,
  '1': 4,
  '1.5': 6,
  '2': 8,
  '2.5': 10,
  '3': 12,
  '3.5': 14,
  '4': 16,
  '5': 20,
  '6': 24,
  '7': 28,
  '8': 32,
  '9': 36,
  '10': 40,
  '11': 44,
  '12': 48,
  '14': 56,
  '16': 64,
  '20': 80,
  '24': 96,
} as const;

/** `3xl` (20) is the card radius; `xl` (12) the search field; `full` every pill. */
export const radius = {
  none: 0,
  xs: 2,
  sm: 4,
  md: 6,
  lg: 8,
  xl: 12,
  '2xl': 16,
  '3xl': 20,
  '4xl': 24,
  '5xl': 32,
  full: 9999,
} as const;

export const fontSize = {
  xs: 12,
  sm: 14,
  base: 16,
  lg: 18,
  xl: 20,
  '2xl': 24,
  '3xl': 30,
  '4xl': 36,
  '5xl': 48,
  '6xl': 60,
  '7xl': 72,
  '8xl': 96,
  '9xl': 128,
} as const;

/**
 * Strings rather than numbers — accepted by every RN version we care about.
 *
 * React Native does **not** synthesise weights the way a browser does. Once a
 * weight-specific family is set (`fontFamily.semibold`), this is ignored on both
 * platforms. It stays exported because it is still correct for a web surface,
 * and because it documents which step a call site means. Set the family, not
 * this, to get bold text in the app.
 */
export const fontWeight = {
  thin: '100',
  extralight: '200',
  light: '300',
  normal: '400',
  medium: '500',
  semibold: '600',
  bold: '700',
  extrabold: '800',
  black: '900',
} as const;

/** Line heights in points, matching Tailwind's numeric leading scale. */
export const lineHeight = {
  '3': 12,
  '4': 16,
  '5': 20,
  '6': 24,
  '7': 28,
  '8': 32,
  '9': 36,
  '10': 40,
  '11': 44,
  '12': 48,
} as const;

/**
 * Tracking in **em**, as authored in the design file.
 *
 * React Native's `letterSpacing` is in points, not em, so these cannot be passed
 * through directly — a value that looks right at 36px is invisible at 12px. Run
 * them through `letterSpacing()` below.
 */
export const tracking = {
  tighter: -0.05,
  tight: -0.025,
  normal: 0,
  wide: 0.025,
  wider: 0.05,
  widest: 0.1,
} as const;

/** Converts em tracking to the points RN expects. */
export function letterSpacing(size: number, em: number): number {
  return size * em;
}

/**
 * Elevation. Single-layer, ambient (X is always 0), scaled around the card
 * shadow: `0 1px 7px` at 4% of `neutral-950`. Blur runs high relative to Y at
 * the small end and tightens as elevation grows, which is how real ambient
 * light behaves.
 *
 * RN 0.76+ supports `boxShadow`; the object form is used over the CSS string so
 * the parameters stay inspectable and typed.
 */
const shadowColor = (opacity: number) => `rgba(10, 13, 13, ${opacity})`;

const shadow = (
  offsetY: number,
  blurRadius: number,
  opacity: number,
): readonly BoxShadowValue[] => [
  { offsetX: 0, offsetY, blurRadius, spreadDistance: 0, color: shadowColor(opacity) },
];

export const elevation = {
  '2xs': shadow(1, 3, 0.02),
  xs: shadow(1, 5, 0.03),
  /** Cards. */
  sm: shadow(1, 7, 0.04),
  /** Dropdowns, the serving unit picker. */
  md: shadow(2, 12, 0.05),
  /** Sheets, popovers. */
  lg: shadow(4, 20, 0.06),
  /** Modals. */
  xl: shadow(8, 32, 0.08),
  /** Full-screen overlays. */
  '2xl': shadow(16, 48, 0.12),
} as const;

/**
 * Geist, per the design.
 *
 * Keyed by weight rather than a single `sans`, because React Native resolves a
 * face by family name alone — `fontFamily: 'Geist'` with `fontWeight: '600'`
 * renders regular, silently. The weight lives in the family name, so a call site
 * names one thing that cannot disagree with itself.
 *
 * Keys mirror `fontWeight` above. Only the four steps the design uses are
 * loaded; add a step here and in `src/app/_layout.tsx` together, or it resolves
 * to the system face at runtime with no error.
 */
export const fontFamily = {
  normal: 'Geist_400Regular',
  medium: 'Geist_500Medium',
  semibold: 'Geist_600SemiBold',
  bold: 'Geist_700Bold',
} as const;
