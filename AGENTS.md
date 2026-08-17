# Food Pad — agent instructions

## The app

Native iOS in `apps/ios/` — SwiftUI, iOS 26 — with a Supabase backend and one Edge Function
in `supabase/functions/food-search/`. Start from `README.md` for how to build and run it,
including the `write-config.sh` step that gives the running app its backend configuration.
Skipping it does not fail the build — it produces an app that launches with no backend.

The SwiftUI migration completed on 2026-08-14 and the React Native app was deleted in PR #53.
`docs/swift-migration.md` and `docs/swift-migration-reference.md` remain the record of how it
was done: architecture, the backend contract, parity scope, and the verification standard.
**Their file paths under `src/` are historical**, but the architecture and backend contract
they describe are current and still binding.

## The project has a knowledge base — read it

`~/Documents/Obsidian Vault` holds the project's history in two topics: **research** (why the
product is shaped this way) and **practice** (every merged PR, every confirmed defect, and
the classes they fall into). Its own `AGENTS.md` is the entry point and governs how to read
and write it.

If the vault is unavailable, report the missing historical context and continue without
inventing or assuming its contents.

Sixty-plus confirmed defects are filed there, each with the reason it survived review, sorted
into classes. **Read `wiki/practice/synthesis.md` before designing anything async, bounded, or
stateful** — and before trusting a green test run. The single most expensive lesson on file is
that the suite once supplied the app's own configuration, so 59 passing tests and an app that
could not start were compatible states.

## Standing constraints

- **400-line diff cap per PR, deletions included.** Propose a split with line estimates and
  let Graem pick. One PR at a time — wait for merge before cutting the next.
- **Fix or argue down every CodeRabbit and Conductor GPT comment before merging.** When
  practice-wiki maintenance is requested, retain a rejected finding and its reasoning too.
- **Semantic design tokens only** at call sites — never a raw hex or a primitive ramp step.
  Light theme only; the design has no dark palette.
- **Documentation rule:** every top-level type and protocol carries a brief `///` — one or
  two sentences — saying what it is for, keeping any *why* the reader would otherwise
  re-learn the hard way. Private and nested implementation needs none, unless something
  non-obvious warrants a *why* comment. `.coderabbit.yaml` holds the matching threshold —
  change them together or not at all.
- **Verification is running, not building.** A PR that compiles and has not been driven is
  not verified. Run every check against the unfixed code first and confirm it fails.
  The Edge Function is drivable too — `cd supabase/functions && deno task verify` — so
  "it cannot be tested without deploying" is no longer a reason to defer a backend change.
- **Never commit or print a secret.** `FDC_API_KEY` is an Edge Function secret and must never
  reach the client.
- **Never bulk-delete Supabase rows.** Every user in this project is anonymous, including
  Graem's phone. Delete only rows you created, by id.
- **Production actions need explicit authorisation** — `supabase db push`,
  `supabase functions deploy`.
