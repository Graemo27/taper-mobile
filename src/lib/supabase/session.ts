/**
 * Anonymous session management.
 *
 * The food-search function rejects the publishable key on its own — it requires
 * `role: "authenticated"` with a subject. An anonymous user satisfies that: it
 * is a real row in `auth.users` carrying `is_anonymous: true`, so the journal
 * can hang off its `sub` later, and the user can attach an email to the same
 * account whenever they want one.
 *
 * The point is that no login screen stands in front of a food lookup. The
 * research this product follows is about how much friction and judgment cost at
 * the moment of capture; an account wall is both.
 */

import { supabase } from './client.ts';

/**
 * In-flight sign-in, shared.
 *
 * Without this, a screen that fires two lookups before the first resolves calls
 * `signInAnonymously` twice and writes two `auth.users` rows for one person.
 * The project caps anonymous sign-ins at 30/hour per IP, so duplicates burn a
 * real budget, not just tidiness.
 */
let pending: Promise<string> | null = null;

async function createAnonymousSession(): Promise<string> {
  const { data, error } = await supabase.auth.signInAnonymously();
  if (error) throw error;

  const id = data.user?.id;
  if (!id) throw new Error('Anonymous sign-in returned no user.');
  return id;
}

/**
 * Returns the current user id, signing in anonymously if there is no session.
 *
 * Safe to call on every lookup: an existing session short-circuits, and
 * concurrent callers share one sign-in.
 */
export async function ensureSession(): Promise<string> {
  const { data } = await supabase.auth.getSession();
  if (data.session?.user.id) return data.session.user.id;

  pending ??= createAnonymousSession().finally(() => {
    pending = null;
  });

  return pending;
}
