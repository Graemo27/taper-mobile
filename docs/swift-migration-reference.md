# Swift migration — product and technical reference

This is the product and technical half of the Swift migration brief. The operational half
will link it in the follow-up documentation PR. Section numbering begins at §4 so the two
halves form one stable brief when that split is complete.

> **Completed 2026-08-14.** The Swift app reached parity, was confirmed on device, and the
> React Native app was deleted in PR #53. This document is kept as the record of how that was
> done and why. **Every path under `src/` in it refers to code that no longer exists** — read
> those as citations, not as places to look. The architecture, backend contract and design
> decisions it describes are current.

---

## 4. Target architecture

### 4.1 Location and toolchain

- **New Swift app at `apps/ios/`.** Do not put it in `ios/` — that directory is Expo
  `prebuild` output, is generated, and gets deleted in the final PR.
- SwiftUI, minimum deployment target **iOS 26**. Xcode 26.4+.
- Bundle identifier `com.graemkrietzman.foodpad`, display name **Food Pad**. Matching the
  existing one means the new build replaces the old one on Graem's phone rather than sitting
  beside it.
- **Swift Package Manager, not CocoaPods.** The existing `ios/Podfile` is Expo's, and nothing
  in it survives.
- Graem is on a **free personal Apple team** — certificates expire every 7 days and the app
  must be rebuilt to keep running on device. Do not design anything around a long-lived
  install. Development runs against the simulator; device runs are Graem's, on request.
- **The build needs a configuration step before `xcodegen generate`:**

  ```sh
  apps/ios/Scripts/write-config.sh   # repository .env -> apps/ios/Config.xcconfig
  ```

  This is the native replacement for Expo inlining `EXPO_PUBLIC_*` into the JS bundle. Skip
  it and the app still compiles, installs and launches — it simply has no backend, and every
  screen reports the same failure it would report if Supabase were down. `Config.xcconfig` is
  gitignored, like the `.env` it derives from.

  `ProcessInfo.processInfo.environment` still wins over the built-in values, which is how
  XCUITest points a build at a different project. That precedence is why the omission went
  unnoticed for the whole migration: **the test suite supplied the configuration itself**, so
  a fully green run and an app that cannot start were compatible states. Any check that only
  ever launches through the harness cannot see this class of defect —
  `testTheAppIsConfiguredWhenLaunchedTheWayAPersonLaunchesIt` is the one that can, because it
  launches with no arguments and no environment at all.

### 4.2 The decisions already made

**Networking is a protocol, and fault injection is built in from the first commit.** Not
added later when something needs testing.

```swift
protocol HTTPClient {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}
```

Return every received HTTP response, including 4xx and 5xx statuses. Throw only when no HTTP
response exists, such as a connection, cancellation, or URL-loading failure. Higher layers
must retain the status when mapping responses to domain and UI states, so a 404 can become
not-found without a retry control.

**Step 1 fault-injection acceptance criteria:** implement launch-argument parsing and an
`HTTPClient` transport that honours this contract:

| Argument | Effect |
|---|---|
| `-FPDelay <seconds>` | Delay the **response**, not the request |
| `-FPDelayURL <substring>` | Apply `-FPDelay` only when the request's absolute URL contains the substring |
| `-FPFail <substring>` | Fail requests whose URL contains the substring |
| `-FPStatus <code>` | Force an HTTP status |

**`-FPDelay` delaying the response rather than the request is not a detail.** Two attempts to
reproduce a real race on PR #32 delayed the request instead, which produces the ordering in
which the bug cannot occur, and both reported success. Read `stale-read-undoes-a-delete`
before implementing this.

Without `-FPDelayURL`, the delay is global. With it, nonmatching requests proceed normally;
the scope changes only the delay and does not fail or rewrite a response. For the stale-read
after-delete test, match a query fragment unique to the journal read rather than the table
path shared by the read and delete. A global delay cannot express "a read that was already
in flight when the delete started", which is the exact scenario that matters.

Before Step 1 is complete, tests must prove argument parsing, delayed-response timing, a
matching scoped URL, and a nonmatching URL that remains undelayed. Run those checks against
an implementation with each behavior disabled first so red is demonstrated.

**Accessibility identifiers on every interactive element and every state container, from the
first commit.** The accessibility tree is the DOM analogue and the only thing XCUITest can
address. Retrofitting them is the expensive path. Use stable, semantic identifiers
(`journal.day.2026-08-12`, `food.save-button`, `search.field`) — never index-based.

**Rejected, so you do not spend time on it: AttributeGraph.** It is private API. It cannot be
used to observe state propagation, and shipping against it is not an option. Use
`Self._printChanges()` in debug builds when you need to know why a view re-rendered.

**Android is not a consideration.** The React Native app is being deleted, not kept for
Android. There are no Android users.

### 4.3 Data layer shape

The app talks to Supabase over PostgREST and to one Edge Function. Use the official
`supabase-swift` package and state the reasoning in the foundation PR. Keep fault injection
at the transport boundary by giving it a custom `URLSession` configuration.

**Anonymous auth must self-heal.** An access token stays cryptographically valid for about
an hour after the user row is deleted; the refresh then fails with a 400 and "Invalid Refresh
Token". On that exact response, clear the persisted stale credentials, coalesce concurrent
recovery behind one fresh anonymous sign-in, and retry the original operation exactly once.
If sign-in or that retry fails, surface the normal typed failure; never loop and never reuse
the stale credentials.

---

## 5. Design tokens

Ported from the Paper file `Food_Pad` into `src/theme/`. **Port the token files first, as
data, before any screen.** They are the reason screens can be judged against the design.

- `src/theme/colors.ts` (141 lines) — two layers: raw ramps (`neutral`, `emerald`, `red`,
  `amber`), then **semantic names that alias them**. Components use the semantic layer only.
- `src/theme/scales.ts` (175 lines) — Tailwind v4 spacing, radius, type scale, shadows.
  Full scales are kept even where only two steps are used, so there is always a sanctioned
  value to reach for.

Two constraints carried from the design work:

- **Light only.** The Paper design has no dark palette and inventing one is design work, not
  a port. Do not add `@Environment(\.colorScheme)` branches. Lock the app to light.
- **Status colours (red / amber / green) are system feedback only.** They never colour a
  food, a nutrient, or a scale. This is a product rule from the research, not a style
  preference — see `judgment-and-shame-in-tracking`.

Fonts are Geist, four weights. Note the metadata trap recorded in
`font-loading-should-move-to-the-config-plugin`: the 400 and 700 files both declare the
family `Geist` while 500 and 600 declare `Geist Medium` and `Geist SemiBold`. iOS registers
fonts under their *embedded* names, so referring to them by family will not disambiguate
Regular from Bold. Use the **PostScript names** — `Geist-Regular`, `Geist-Medium`,
`Geist-SemiBold`, `Geist-Bold`.

---

## 6. The backend does not change

**No migrations. No Edge Function changes. No schema changes.** The Swift app is a new client
for an existing, working backend. If you believe a backend change is required, stop and ask —
it is more likely a misreading of the current client.

### Tables

**`journal_entries`** — one row per food logged, per day.
`id` (identity), `user_id`, `eaten_on` (date), `created_at`, `fdc_id`, `name`,
`serving_label`, `servings` (1–20), `grams`, `kcal`, `protein_g`, `fibre_g`.

Two properties to preserve in the Swift client:

- **Entries are a snapshot, not a reference.** FDC revises its data; a record of what someone
  ate on a Tuesday must not change because the USDA restated a figure. This is also why the
  Journal renders without any lookup.
- **`eaten_on` is the reader's local date, supplied by the client.** Deriving it server-side
  would use the server's clock, and "today" in UTC is yesterday for much of the world.
  Send a local `YYYY-MM-DD` string. Keep dates as strings end to end — parsing them into
  `Date` files an evening's entry under the previous day west of Greenwich.
- **Nulls are FDC gaps, never zeroes.** A missing kcal renders as nothing, not as "0".

**`favourites`** — `(user_id, fdc_id)` composite primary key, plus `created_at`. Only the
reference is stored: unlike a journal entry, a favourite points at whatever that food *is
now*, so a USDA revision should reach it.

RLS is on for both, scoped to `authenticated` (which is what an anonymous sign-in is). There
is **no update policy on either table** — nothing in the app edits a row. The journal removes
and re-adds; a favourite is an insert or a delete. Do not write an update path.

### Edge Function: `food-search`

Deployed at version 3. Two routes on one function, both `POST`:

- `{ query: string }` → search results (`FoodHit[]`)
- `{ fdcId: number }` → one resolved food (`Food`)

A body carrying both is treated as by-id. Invalid ids (`-5`, `1.5`, `"abc"`) answer 400.

**404 is forwarded, not flattened to 502.** A food FDC will not serve is an answer, not an
outage — and the UI must offer "Try again" only for the outage. Retrying a 404 asks the same
question forever.

### Domain types

`src/lib/food/types.ts` is the contract and it is deliberately narrower than FDC's response.
Mirror it in Swift:

- `Portion` — `label` (shown verbatim), `grams`
- `Nutrients` — `kcal`, `proteinG`, `fibreG`, `vitaminEMg`, `magnesiumMg`,
  `unsaturatedFatG`. **Every field is optional**, because FDC coverage is uneven — Foundation
  foods frequently omit Energy entirely. `unsaturatedFatG` is mono + poly summed here,
  because FDC reports them separately and names neither "unsaturated".
- `FoodHit` — `fdcId`, `name`, `category?`, `dataType`
- `Food: FoodHit` — plus `portion?`, `per100g`, `perServing?`, `portions[]`

Use `Double?` / `Int?`. Do not default a missing nutrient to zero anywhere in the stack.

---

## 7. Parity: what must exist

Four screens. Line counts are the current TypeScript, as a rough sense of weight.

### Journal (`src/app/index.tsx`, 293 lines) — the root screen

- Days newest first; each day a heading over a card of entries
- Headings read "Today", "Yesterday", then "Sunday, August 9"
- **A count beside the heading, and no total, no goal, no streak.** This is the product's
  central constraint, not an unfinished feature. Read `judgment-and-shame-in-tracking` before
  touching it.
  - Preserve the shipped wording, **"things"**, through parity. Revisit "items" during M2.
- Entries show name, serving label, kcal. A null kcal or serving label is **omitted**, not
  rendered as zero or a blank line.
- States: loading skeleton, empty ("Nothing written down yet"), failure with retry
- **The failure renders beneath the days, not instead of them**, worded for which case
  occurred — "Could not open your journal" with nothing on screen, "Could not check for new
  entries — this is what was here when it last read" with days behind it
- Swipe a row left to reveal **Remove**: 88pt panel, the design's red, trash icon over label.
  No confirm step, no undo. Optimistic — the row goes immediately and returns with a notice
  if the delete fails.
- VoiceOver gets removal as an accessibility action, since a swipe is invisible to anyone not
  making one
- The read is a **30-day window** with `count: 'exact'` truncation detection
- **A timer to the next midnight** that re-arms daily

### Search (`src/app/search.tsx`, 177 lines)

- Search field; results as cards; skeleton while loading; a no-matches state; a failure state
- **Recent** card on the empty screen: foods already logged, deduped to the newest entry per
  food, refreshed **on focus** (not on appear-once)
- A failed Recent read is **silent**. It is an offer, not an answer to a question anyone
  asked, and an error card would report a failure nobody was waiting on.
- Favourited rows show a gold star and announce "favourite"
- Tapping a result hands the resolved food to Food detail so it has nothing to fetch;
  tapping a Recent row navigates on the id alone

### Food detail (`src/app/food/[id].tsx`, 315 lines)

- Reachable by hand-off from Search **and** by id alone (`/food/170567` must work)
- Nutrition card, "high in" chips, serving picker with a 1–20 stepper
- Save to today, with a **2.4-second** "Saved to today" confirmation that reverts
- Favourite toggle
- States: loading, not-found (no retry control), failure (with retry)
- **The not-found copy must not name a cause.** It cannot distinguish "FDC withdrew this
  food" from "that id was never valid" — read `not-found-copy-names-a-cause-it-cannot-know`.

### Shared logic worth porting rather than rewriting

- **`src/lib/food/format.ts` (250 lines)** — the most logic-dense file in the app, and the one
  you should port **case for case rather than re-derive**. It handles pluralising a scaled
  serving label, and it took three attempts: a hand-written noun list missed "1 pita, large"
  on the next food opened; a general rule, run over **139 real FDC labels**, produced
  `20 pieceses`, `4 biscuitses`, `0.33 ofs`, `2 Nleas serving`, `2 cubics inch`, and
  `606 xes 406`. The current version names each of those as a case. Re-deriving this will
  reproduce the same three passes. Read `a-scaled-portion-loses-its-plural`.
  - Sizes stay singular deliberately: "1 medium" is a whole banana; two are "2 medium".
  - Two shapes are descriptions rather than counts — `1/6 of 16 oz cake`, `303 x 406` — and
    are left exactly as FDC wrote them.
- `src/lib/journal/days.ts` (86 lines) — grouping and heading text
- `src/lib/food/parse.ts` (187 lines) — FDC response → domain types
- `src/lib/food/claims.ts` (62 lines) — the "high in" thresholds

---
