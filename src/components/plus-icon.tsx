/**
 * A plus, drawn with two bars rather than an SVG path.
 *
 * `react-native-svg` is not a dependency yet and this is the only icon the app
 * has. It arrives with the Search screen, which needs four at once — search,
 * chevron, alert, retry — and that is where the dependency pays for itself.
 * Until then, one glyph does not justify it.
 */

import { View } from 'react-native';

import { radius } from '@/theme';

export function PlusIcon({
  size = 18,
  stroke = 2,
  color,
}: {
  size?: number;
  stroke?: number;
  color: string;
}) {
  // The design's plus spans 11 of an 18px box, so the bar is the visual mark
  // and `size` is the slot it sits in — matching how the SVG was exported.
  const bar = Math.round(size * 0.61);

  const common = {
    position: 'absolute',
    backgroundColor: color,
    borderRadius: radius.full,
  } as const;

  return (
    <View
      style={{ width: size, height: size, alignItems: 'center', justifyContent: 'center' }}
    >
      <View style={{ ...common, width: bar, height: stroke }} />
      <View style={{ ...common, width: stroke, height: bar }} />
    </View>
  );
}
