/**
 * The app's Supabase client.
 *
 * Note the contrast with `FDC_API_KEY`: these two values are *meant* to be
 * public. Expo inlines every `EXPO_PUBLIC_*` var into the bundle, which is why
 * the FDC key must never be one — but a project URL and a publishable key are
 * designed to ship inside every install. What protects the data is auth and RLS,
 * not the secrecy of these strings.
 *
 * Publishable (`sb_publishable_…`) rather than the legacy `anon` JWT: it rotates
 * independently of the project's JWT secret, and Supabase now treats the legacy
 * key as compatibility-only.
 */

import AsyncStorage from '@react-native-async-storage/async-storage';
import { createClient } from '@supabase/supabase-js';
import { AppState } from 'react-native';

const url = process.env.EXPO_PUBLIC_SUPABASE_URL;
const publishableKey = process.env.EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

if (!url || !publishableKey) {
  // Inlined at build time, so a miss is a broken build rather than a runtime
  // blip on one device. Failing loudly here beats a confusing 401 later.
  throw new Error(
    'EXPO_PUBLIC_SUPABASE_URL and EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY are missing. Copy .env.example to .env.',
  );
}

/**
 * `expo export --platform web` prerenders every route in Node, where there is
 * no window and no storage. Returning empty rather than touching AsyncStorage
 * keeps the static build from crashing; the session is read again on the client
 * where it actually exists.
 */
const isServer = typeof window === 'undefined';

const storage = {
  getItem: (key: string) => (isServer ? Promise.resolve(null) : AsyncStorage.getItem(key)),
  setItem: (key: string, value: string) =>
    isServer ? Promise.resolve() : AsyncStorage.setItem(key, value),
  removeItem: (key: string) => (isServer ? Promise.resolve() : AsyncStorage.removeItem(key)),
};

export const supabase = createClient(url, publishableKey, {
  auth: {
    storage,
    persistSession: true,
    autoRefreshToken: true,
    // No OAuth redirect to parse. Anonymous sign-in is the only entry, and
    // leaving this on makes the client inspect the URL on every web load.
    detectSessionInUrl: false,
  },
});

// Off the browser, supabase-js refreshes *continuously* in the background —
// it has no visibility signal of its own to hook into. Left alone that wakes
// the radio on a backgrounded phone forever. Registered once, at module scope,
// because the docs are explicit that repeat registration is a bug.
if (!isServer) {
  AppState.addEventListener('change', (state) => {
    if (state === 'active') {
      void supabase.auth.startAutoRefresh();
    } else {
      void supabase.auth.stopAutoRefresh();
    }
  });
}
