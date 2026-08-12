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

/**
 * The failure mark. Red is doing system-feedback work here — a lookup that did
 * not happen — which is the only thing status colour is allowed to do in this
 * app. It never touches a food, a nutrient, or the processing scale.
 */
export function AlertIcon({ size = 22, color = colors.error }: IconProps) {
  return (
    <Svg width={size} height={size} viewBox="0 0 24 24">
      <Circle cx="12" cy="12" r="9.25" fill="none" stroke={color} strokeWidth="1.5" />
      <Path d="M12 7.5V13" fill="none" stroke={color} strokeWidth="1.5" strokeLinecap="round" />
      <Circle cx="12" cy="16.25" r="1" fill={color} />
    </Svg>
  );
}

/** An open arc with a head, so it reads as "again" rather than "loading". */
export function RetryIcon({ size = 15, color = colors.onBrand }: IconProps) {
  return (
    <Svg width={size} height={size} viewBox="0 0 16 16">
      <Path
        d="M13.5 8A5.5 5.5 0 1 1 11.6 3.9"
        fill="none"
        stroke={color}
        strokeWidth="1.5"
        strokeLinecap="round"
      />
      <Path
        d="M13.6 1.9V5.1H10.4"
        fill="none"
        stroke={color}
        strokeWidth="1.5"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </Svg>
  );
}

/**
 * Points left, and heavier than the row chevron — this one is a control with a
 * label beside it, not a hint at the end of a row. Its own path rather than a
 * rotated `ChevronIcon`, because the design draws it at 2.2 against 2.
 */
export function BackChevronIcon({ size = 15, color = colors.brand }: IconProps) {
  return (
    <Svg width={(size * 9) / 15} height={size} viewBox="0 0 9 15">
      <Path
        // Ends inset 0.1 from the design's 8/1/14: at stroke 2.2 the round caps
        // reach 1.1 further and clipped flat. Elbow stays, so the angle does.
        d="M7.9 1.1L1.5 7.5 7.9 13.9"
        fill="none"
        stroke={color}
        strokeWidth="2.2"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
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
