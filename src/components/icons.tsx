/**
 * Line icons, drawn to the paths in the Paper file rather than pulled from a set.
 *
 * The plus glyph on the Journal was two `View`s — a magnifier is not, so this is
 * where `react-native-svg` earns its place. `size` scales the rendered box; the
 * viewBox and stroke widths stay as authored, so the weight tracks the size the
 * way the design's do.
 */

import Svg, { Circle, Path } from 'react-native-svg';

import { colors } from '@/theme';

interface IconProps {
  size?: number;
  color?: string;
}

export function SearchIcon({ size = 17, color = colors.textSecondary }: IconProps) {
  return (
    <Svg width={size} height={size} viewBox="0 0 24 24">
      <Circle cx="11" cy="11" r="7" fill="none" stroke={color} strokeWidth="2.2" strokeLinecap="round" />
      <Path d="M20 20l-3.5-3.5" fill="none" stroke={color} strokeWidth="2.2" strokeLinecap="round" />
    </Svg>
  );
}

/** Points right. The row affordance, not a control — rows carry their own press. */
export function ChevronIcon({ size = 14, color = colors.textSecondary }: IconProps) {
  return (
    <Svg width={(size * 8) / 14} height={size} viewBox="0 0 8 14">
      <Path
        d="M1 1l6 6-6 6"
        fill="none"
        stroke={color}
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </Svg>
  );
}
