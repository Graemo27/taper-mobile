/**
 * Design tokens for Food Pad, ported from the Paper file `Food_Pad`.
 *
 * Import from here, not from the individual modules.
 *
 * Note: `src/constants/theme.ts` is the Expo template's own theme and is a
 * separate, conflicting system — different spacing scale, light/dark colours we
 * do not use. It still backs the template screens, so it stays until those are
 * replaced, at which point it goes.
 */

export { amber, black, colors, emerald, green, neutral, red, white } from './colors.ts';
export type { ColorToken } from './colors.ts';

export {
  elevation,
  fontFamily,
  fontSize,
  fontWeight,
  letterSpacing,
  lineHeight,
  radius,
  spacing,
  tracking,
} from './scales.ts';
