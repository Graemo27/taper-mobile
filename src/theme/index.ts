/**
 * Design tokens for Food Pad, ported from the Paper file `Food_Pad`.
 *
 * Import from here, not from the individual modules.
 *
 * This is now the only theme in the app. `src/constants/theme.ts` — the Expo
 * template's competing light/dark palette and spacing scale — went out with the
 * template screens it backed.
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
