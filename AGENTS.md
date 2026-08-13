# Food Pad — agent instructions

## Active work: the SwiftUI migration

The React Native app is being ported to SwiftUI and then deleted. **Read
`docs/swift-migration.md` and `docs/swift-migration-reference.md` in full before writing any
code.** Together they are the complete brief: architecture, the backend contract, parity
scope, the PR sequence, and the verification standard.

## The project has a knowledge base — read it

`~/Documents/Obsidian Vault` holds the project's history in two topics: **research** (why the
product is shaped this way) and **practice** (every merged PR, every confirmed defect, and
the classes they fall into). Its own `AGENTS.md` is the entry point and governs how to read
and write it.

Fifteen defects from the last five PRs are filed there with the reason each one survived
review. **They are ported code's problem, not React Native's** — read
`wiki/practice/synthesis.md` before designing anything async, bounded, or stateful.

## Standing constraints

- **400-line diff cap per PR, deletions included.** Propose a split with line estimates and
  let Graem pick. One PR at a time — wait for merge before cutting the next.
- **Fix or argue down every CodeRabbit and Conductor GPT comment before merging.** A rejected
  finding with its reasoning gets filed too.
- **Semantic design tokens only** at call sites — never a raw hex or a primitive ramp step.
  Light theme only; the design has no dark palette.
- **Verification is running, not building.** A PR that compiles and has not been driven is
  not verified. Run every check against the unfixed code first and confirm it fails.
- **Never commit or print a secret.** `FDC_API_KEY` is an Edge Function secret and must never
  reach the client.
- **Never bulk-delete Supabase rows.** Every user in this project is anonymous, including
  Graem's phone. Delete only rows you created, by id.
- **Production actions need explicit authorisation** — `supabase db push`,
  `supabase functions deploy`.

## While the React Native app still exists

Expo has changed since most training data. Read the exact versioned docs at
https://docs.expo.dev/versions/v57.0.0/ before editing anything under `src/`. This stops
applying once the migration reaches parity and `src/` is deleted.
