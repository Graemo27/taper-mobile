import { Geist_400Regular } from '@expo-google-fonts/geist/400Regular';
import { Geist_500Medium } from '@expo-google-fonts/geist/500Medium';
import { Geist_600SemiBold } from '@expo-google-fonts/geist/600SemiBold';
import { Geist_700Bold } from '@expo-google-fonts/geist/700Bold';
import { useFonts } from 'expo-font';
import { DarkTheme, DefaultTheme, ThemeProvider } from 'expo-router';
import * as SplashScreen from 'expo-splash-screen';
import { useColorScheme } from 'react-native';

import { AnimatedSplashOverlay } from '@/components/animated-icon';
import AppTabs from '@/components/app-tabs';

SplashScreen.preventAutoHideAsync();

export default function TabLayout() {
  const colorScheme = useColorScheme();

  // Imported per weight, not from the package root — the root barrel `require`s
  // all eighteen faces, so Metro would bundle regular and italic at every step
  // for the four the design uses.
  //
  // The keys are the names components reference through `fontFamily` in
  // src/theme/scales.ts. SDK 57 prefers the expo-font config plugin, which
  // embeds faces at build time, but that needs a dev build; this works in Expo
  // Go today and is the swap to make when the project gains native projects.
  const [fontsLoaded, fontError] = useFonts({
    Geist_400Regular,
    Geist_500Medium,
    Geist_600SemiBold,
    Geist_700Bold,
  });

  // Held behind the native splash, which `preventAutoHideAsync` above keeps up
  // until AnimatedSplashOverlay mounts — otherwise the first frame paints in the
  // system face and reflows once Geist arrives.
  //
  // A font error still renders: text falls back to the system face, which is
  // worse-looking but readable. A blank screen is not a better failure.
  if (!fontsLoaded && !fontError) return null;

  return (
    <ThemeProvider value={colorScheme === 'dark' ? DarkTheme : DefaultTheme}>
      <AnimatedSplashOverlay />
      <AppTabs />
    </ThemeProvider>
  );
}
