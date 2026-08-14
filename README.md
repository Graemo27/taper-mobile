# Food Pad

A food journal that does not grade you. You write down what you ate; it shows you
the days, and nothing else. No daily total, no goal, no streak — that constraint is
the product, not an unfinished feature, and the reasoning behind it is in the
project's knowledge base rather than in this file.

Native iOS, SwiftUI, with a Supabase backend and one Edge Function.

## Layout

```text
apps/ios/            The app. SwiftUI, iOS 26, XcodeGen-generated project
supabase/functions/  food-search — the FDC proxy, Deno/TypeScript
supabase/migrations/ Schema, applied in order
docs/                The SwiftUI migration brief and its reference
```

The React Native app this replaced lived in `src/` and was deleted once the Swift
app reached parity on device. `docs/swift-migration.md` records how that was done
and why; its file paths under `src/` are historical.

## Running it

You need Xcode 26.4+, [XcodeGen](https://github.com/yonaskolb/XcodeGen), and a
`.env` — copy `.env.example` and fill it in.

```sh
apps/ios/Scripts/write-config.sh   # .env -> apps/ios/Config.xcconfig
cd apps/ios && xcodegen generate
open FoodPad.xcodeproj
```

**Do not skip the first step.** It writes the Supabase settings into the build, the
way Expo used to inline `EXPO_PUBLIC_*` into the JS bundle. Without it the app
compiles, installs and launches perfectly well with no backend, and every screen
reports what looks like a network outage. That exact omission shipped once and was
caught only by running the app on a phone.

`Config.xcconfig` is gitignored, like the `.env` it derives from.

### Tests

```sh
cd apps/ios
xcodebuild test -scheme FoodPad -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

**Watch the skip count, not just the failures.** One test creates a real row in the
live database, swipes it away for real, and confirms the deletion through a fresh
read — and it skips itself when `.env` is missing. A run reporting zero failures and
a nonzero skip count means that test quietly did not run.

### Device builds

Signing uses a free personal Apple team, so provisioning profiles expire after seven
days and the app must be rebuilt to keep running. Sign in under Xcode → Settings →
Accounts first; after that `xcodebuild -destination 'id=<device-udid>'` works from
the command line.

## Conventions

`AGENTS.md` holds the working rules — the diff cap, the documentation rule, the
design-token rule, and the standing prohibitions around secrets and production
data. Read it before changing anything here.
