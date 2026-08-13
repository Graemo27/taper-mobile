# Food Pad — React Native → SwiftUI migration

**Owner of this work: Codex.** Graem is working on M2 design in parallel and is not editing
app code while this runs.

This document and `swift-migration-reference.md` are the complete brief. They assume no
knowledge of the conversations that produced the current app — everything required is in
them or in one of the places they point at.

**Scope: reach parity with the shipped React Native app in SwiftUI, then delete the React
Native app.** No new features. M2 is a separate, later effort and is explicitly out of scope
(see §10).

---

## 1. Read these first, in this order

1. **This file**, following its instruction after §3 to read
   `swift-migration-reference.md` before continuing to §8.
2. **`~/Documents/Obsidian Vault`** — the project's knowledge base. Its `AGENTS.md` is your
   entry point there and tells you how to read and write it. §2 below tells you which pages
   matter for *this* task.
3. **The existing app**, under `src/`. 4,533 lines of TypeScript. It is the specification for
   parity, and its comments are unusually load-bearing — many of them record a measurement
   that cost real time to obtain.

Do not read Expo documentation for work confined to `apps/ios/`; Expo is the client being
replaced. If a task edits the still-live React Native app under `src/`, the repo root
`AGENTS.md` still requires the exact Expo v57 documentation first.

---

## 2. The Obsidian vault is the project's history — use it

This is the part most likely to be skipped and the part most likely to save you a week.

The vault at `~/Documents/Obsidian Vault` holds two topics. **`wiki/research/`** is outside
evidence about food journaling and explains *why the product is shaped the way it is*.
**`wiki/practice/`** is the record of building it: every merged PR, every confirmed defect
accepted or rejected, and the classes those defects fall into.

`wiki/practice/` was filed on 2026-08-13 covering PRs #28–#32 — 5 change pages, 15 defect
pages, 8 concept pages. **Fourteen of those fifteen defects are ported code's problem, not
React Native's.** They will recur in Swift unless you design against them.

### Before you write any code

Read, in this order:

- `wiki/practice/synthesis.md` — the whole summary in one page
- `wiki/practice/concepts/stale-async-result.md` — the largest class, 6 instances
- `wiki/practice/concepts/verification-that-tests-the-wrong-thing.md` — 8 instances, and the
  reason the verification section of this document is as prescriptive as it is

### Before you touch a specific area

| Working on | Read |
|---|---|
| Anything async near navigation | `stale-async-result`, and the 4 defect pages it links |
| The journal read / any bounded query | `silent-truncation`, `the-row-cap-splits-a-day` |
| Any loading / error / empty state | `state-with-no-rendered-branch` |
| Any user-facing error copy | `copy-names-a-cause-the-state-cannot-know` |
| Serving labels and pluralisation | `a-scaled-portion-loses-its-plural`, `cases-enumerated-from-a-sample` |
| The "Today" heading, or any date | `state-that-changes-with-no-event` |
| Why there is no calorie total or streak | `wiki/research/synthesis.md`, `judgment-and-shame-in-tracking` |

### Writing back to the vault

The vault's `AGENTS.md` governs this and takes precedence over anything here. Two points that
matter for this task specifically:

- **Use `caught-by: codex`** when you are the first to surface a confirmed defect. Not
  `claude`, not a review tool that repeated it later.
- **Never invent a reason a defect survived.** The `## Why it survived until then` section is
  required on every defect page and is the entire value of the page. If the record does not
  establish the reason, stop and ask Graem.
- The vault's `AGENTS.md` names the repo as `~/Documents/GraemOS/food-pad`. **This work may
  be happening in a different checkout** — confirm the path you are in rather than assuming.

Filing is not part of the migration PRs. Do it when Graem asks, or when a task explicitly
includes it.

---

## 3. Ground rules

These are Graem's standing constraints on this repository. They are not negotiable defaults;
they came from things going wrong.

**PR size: hard cap of 400 lines of diff, deletions included.** Propose a split with
per-PR line estimates before opening anything, and let Graem pick the granularity.

Every PR in §9 carries a line estimate against that cap. **Check the real number before
opening** — `git diff --stat` against the base branch — and if it is over, say so in the PR
description and propose the split rather than opening it quietly. Going over has been agreed
before (PR #28 shipped at 523) but it was agreed *in advance*, not discovered in review.

Graem has approved two narrow exceptions where generated or removed lines would make the
cap measure review noise instead of authored code:

> **1. Generated Xcode files.** Generated `project.pbxproj`, asset-catalog metadata, and
> scheme XML are excluded. Hand-written Swift and hand-written configuration still count.

> **2. Pure deletion of the React Native app.** The final removal is excluded only while it
> remains pure deletion. Any authored replacement or configuration change counts and should
> be reviewed separately.

State the relevant exception in the PR description; neither is a general cap exemption.

**One PR at a time.** Wait for merge before cutting the next. Stacking has lost commits here
twice.

**Fix every CodeRabbit and Conductor GPT review comment before merging** — or argue it down
in writing. A rejected finding with its reasoning is worth as much as an accepted one, and
both get filed. See `an-upper-date-bound-hides-a-real-entry` for what a good rejection looks
like.

**Style with semantic tokens only.** Never a raw hex value, never a primitive ramp step, at a
call site. §5 covers the token port.

**Secrets.** `.env` / `.env.local` are gitignored. Never commit a secret and never print one
in output — not even partially. `FDC_API_KEY` is a Supabase Edge Function secret and **must
never reach the client under any circumstances**; USDA deactivates keys that appear in
shipped bundles. The only two values the app needs are the Supabase URL and the
**publishable** key.

**Production Supabase actions require explicit authorisation** from Graem —
`supabase db push`, `supabase functions deploy`. None should be needed here; see §6.

**Never bulk-delete rows in the production database.** Every user in this project is
anonymous, including Graem's phone, so `delete from auth.users where is_anonymous` destroys
his real session. Delete only rows you created, by id, and clean up after every test cycle.

---

## 4–7. Product and technical reference

Read `swift-migration-reference.md` now, in full. It contains the target architecture,
design tokens, backend contract, and parity scope with the original §4–§7 numbering
preserved. Return here for §8 after reading it.

## 8. Verification

**The standard on this project is running, not building.** A PR that compiles and has not
been driven is not verified. This section is prescriptive because the single most common
defect class in the project's history is verification that reported success on broken code —
8 recorded instances. Read `verification-that-tests-the-wrong-thing`.

### The tooling

- `xcrun simctl boot | install | launch` — drive the app
- `xcrun simctl io <udid> screenshot` — visual check against the Paper boards
- `xcrun simctl status_bar <udid> override --time 9:41` — stable screenshots
- `xcrun simctl spawn <udid> log stream` — runtime logging
- **XCUITest** — the accessibility tree is the DOM analogue, and unlike the old web harness
  it drives the real binary
- Launch-argument fault injection (§4.2) for every failure and race case; use
  `-FPDelayURL` whenever only one side of a race may be delayed

### Four rules, each of which exists because it was violated

1. **Run every check against the unfixed code first and confirm it fails.** A green result is
   only evidence if red is reachable. This one rule has caught more than everything else on
   this page combined.
2. **Sample temporary states repeatedly across their window, never once.** A single assertion
   at 8.7s against a 2.4-second confirmation reported "no bug" for a real one. The "Saved to
   today" confirmation is exactly such a state and you will be testing it.
3. **For a race, delay the side of the round trip the race is actually about.** Delaying the
   wrong side does not weaken the test — it inverts it, constructing the ordering in which
   the bug cannot occur, and then reporting success.
4. **Do not construct the input the library under test produces.** A harness once fed a
   hand-made `AbortError` — the shape the SDK was assumed to emit. It passed and proved
   nothing, because the SDK wraps it and that shape never occurs. Take the error from the
   library.

### Why this migration is happening at all

The old harness was a served `expo export --platform web` build driven in Chrome. It has a
boundary that was found the hard way: **synthetic pointer events do not drive
react-native-gesture-handler.** The swipe-to-remove panel stayed shut while the accessibility
tree happily reported a "Remove" button that no click could reach. A naive run produced a
green result for a feature that did not work, and the gesture could only be checked by hand
on a phone.

That defect is filed as **open** at
`wiki/practice/defects/the-swipe-gesture-cannot-be-driven-by-the-harness.md`, and closing it
is a deliverable of this migration. **The Recent foods and swipe removal PR must include an
XCUITest that performs a real swipe and asserts the row is gone** — from the accessibility
tree *and* from the database.

### Test data hygiene

Tests write to the production database. Delete every row you create, by id, after each cycle,
and say so in the PR. Never issue a bulk delete (§3).

---

## 9. PR sequence

Line estimates count hand-written Swift and configuration. Generated Xcode metadata is
excluded under the recorded exception in §3.

Completed groundwork:

- **PR #33, Bootstrap the SwiftUI project — merged.** Generated Xcode and asset metadata,
  copied binary assets, the app entry point, and a minimal launchable screen. Networking,
  tokens, and substantive tests were deliberately deferred for review.
- **PR #34, Scaffold the native test targets — merged.** Generated test-target metadata and
  disposable launch smoke tests.
- **PR #35, Document the Swift migration reference — merged.** The architecture, backend
  contract, design tokens, and parity scope now live in `swift-migration-reference.md`.

The remaining implementation sequence begins now. These are migration steps, not GitHub PR
numbers; the next implementation PR is Step 1.

| Step | PR | Est. | Contents |
|---|---|---|---|
| 1 | Foundation and the harness that proves itself | ~320 | `HTTPClient` + fault injection; design tokens as data; static Journal foundation; replace the smoke assertions with an XCUITest that reads stable accessibility identifiers |
| 2 | Session and the journal read | ~380 | Anonymous auth with self-healing refresh; `journal_entries` read with the 30-day window and exact-count truncation; Journal screen with all four states; the midnight timer |
| 3 | Food formatting and parsing | ~320 | `parse.ts` → domain types; **`format.ts` ported case for case**; `claims.ts` thresholds. Pure logic, no UI |
| 4 | Search and food detail | ~390 | Edge Function client, both routes; results list with its four states; food detail with nutrition and "high in"; the serving stepper |
| 5 | Save and favourites | ~300 | Save to today; the 2.4s confirmation, keyed by food id; the favourite toggle; both optimistic |
| 6 | Recent foods and swipe to remove | ~350 | Recent on the empty search screen, refreshed on focus, failing silently; swipe-to-remove with optimistic delete and rollback; **the XCUITest that closes the open defect** |
| 7 | Parity check | ~30 | Screen-by-screen against the Paper boards. Fixes only. **No deletions.** |
| 8 | Delete the React Native app | exempt deletion | Pure deletion, ~4,500 lines; open only after Graem confirms parity on his phone |

**PR 3 was split out of Search deliberately.** `format.ts` is 250 lines of TypeScript and will
be longer in Swift; leaving it inside the Search PR guarantees a breach. It is also pure
logic with no UI, which makes it the one part of this migration that can be verified against
a table of inputs rather than by driving the app — worth its own review for that reason
alone.

### The deletion exception

Removing the React Native app is about 4,500 deleted lines. Graem approved a pure-deletion
exception because splitting `git rm` by directory would satisfy the letter of the cap without
improving review. Keep authored changes out of that PR so the exception stays narrow.

Step 1 is deliberately not a feature. Its purpose is to prove the verification loop
works before anything depends on it. If the loop does not hold up, that is far cheaper to
discover at 320 lines than at parity.

**Do not open the deletion PR until Graem has confirmed parity himself, on his phone.**

---

## 10. Explicitly out of scope

M2 is a redesign already drafted in Paper, and Graem is working on it in parallel. **None of
it belongs in this migration.** Building parity against a design that is being replaced is
still the right call — it is the only way to know the Swift app works before the shape
changes underneath it.

Not in scope: the calculator interface and its emoji keys; bottom navigation; meals with
titles containing multiple foods (a schema change); the confirmation screen; the emoji
generation API; removing the processing section; custom and editable calculator keys.

If M2 work seems necessary to complete a parity task, it is not. Ask.

---

## 11. Definition of done

- [ ] Every screen in §7 works in the simulator, driven and screenshotted, not just compiled
- [ ] Every failure and race case exercised through launch-argument fault injection, with
      each check shown failing against unfixed code first
- [ ] An XCUITest drives a real swipe and asserts removal in both the accessibility tree and
      the database
- [ ] Graem has run it on his phone and confirmed parity
- [ ] The React Native app is deleted; `supabase/` is untouched
- [ ] Any defect found along the way is filed in `wiki/practice/` with `caught-by: codex`
- [ ] `the-swipe-gesture-cannot-be-driven-by-the-harness` is updated from `open` to resolved,
      with the XCUITest as the evidence

---

## 12. Decisions recorded before the foundation PR

1. Generated Xcode metadata does not count toward the cap; hand-written Swift and
   configuration do. Pure React Native deletion is also exempt when isolated in its own PR.
2. Use `supabase-swift`; keep fault injection at the transport boundary.
3. A free personal-team certificate that expires every seven days is acceptable.
4. Preserve the shipped wording, **"things"**, through parity. Revisit it during M2.
