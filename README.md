# Shengji · Tractor

An iPhone and iPad app that teaches **Shengji** (升级 shēngjí, "Level Up"), the Chinese trick-taking
card game also known as **Tractor** (拖拉机 tuōlājī), and lets you practise against bots.

Fixed partners, a trump suit and a trump rank that change every round, pairs and tractors: Shengji
has a lot of rules to hold in your head at once. The app teaches the classic game for four players and two decks
(bigger groups add decks, about half a deck per player) one small idea at a time, then lets you play real games while
a coach explains what is happening.

## How it teaches

The teaching side is built on well-tested learning science:

- **Spaced repetition.** Every skill and fact you learn is scheduled for review just before you would
  forget it. The Review tab shows what is due.
- **Retrieval practice.** Lessons end with a quiz and daily review is all recall, never re-reading.
- **Interleaving.** Review mixes question types, and lesson quizzes bring back items from earlier lessons.
- **Worked examples.** Each lesson shows real cards and a worked example before asking you to try, and
  asks you to predict ("who wins this trick?") before it explains.
- **Coached play.** At the table a coach explains every trick and gives hints with reasons. Its help
  fades from Guided (trumps marked, cards you can't play dimmed) to Coached to Solo, and a mistake at
  the table brings the related skill back for review.

Every answer, right or wrong, shows the rule behind it. See [DESIGN.md](DESIGN.md) for the full list.

## Run the app

You need a Mac with **Xcode 16 or later**. The app runs on iOS 17 and later.

1. Open `Shengji.xcodeproj` in Xcode.
2. Choose the **Shengji** scheme and an iPhone simulator in the toolbar.
3. Press **Run** (⌘R).

Xcode resolves the local `ShengjiCore` package by itself; the app has no third-party dependencies.

**On your own iPhone:** select the project in the navigator, then the **Shengji** target, then
**Signing & Capabilities**, and pick your **Team**. If Xcode says the bundle identifier is not
available, change `com.mrellcrane.shengji` to something unique, such as `com.yourname.shengji`.
Then connect your iPhone, pick it as the run destination and press Run.

- The first time, turn on **Developer Mode** on the iPhone: Settings > Privacy & Security > Developer
  Mode (it shows up once the iPhone has been connected to Xcode). Let the iPhone restart, confirm
  Developer Mode when it asks, then press Run again.
- If the app won't open because of an "Untrusted Developer", go to Settings > General > VPN & Device
  Management, tap your account under **Developer App** and trust it. This happens with a free Apple
  Account, and apps signed that way stop opening after 7 days until you run them from Xcode again.

**Demo scenes:** launching with `-ScreenshotScene <name>` opens a fixed scene without touching your
saved progress. Names: `learn`, `lesson`, `predict`, `review`, `quiz`, `game`, `dealing`, `result`,
`rules`. The shared scheme already has `-ScreenshotScene game` under Product > Scheme > Edit Scheme >
Run > Arguments; tick it (and change the name) to use it.

## Project structure

```
Shengji.xcodeproj          The app project (one iOS target, "Shengji")
Shengji/                   The SwiftUI app
  App/                     App entry, tabs, persistence stores, demo scenes
  Learn/                   Lessons, review and practice, rules reference, progress
  Game/                    The play-against-bots table
  Shared/                  Theme, card views and other shared UI
  Assets.xcassets          App icon (light, dark and tinted) and accent colour
ShengjiCore/               Swift package with all game and learning logic (no UI)
  Sources/ShengjiCore/
    Engine/                Cards, trumps, combinations, rules, scoring, rounds, games
    Bots/                  Bot players (they also power hints)
    Learning/              Spaced repetition, progress, drills, curriculum
  Tests/ShengjiCoreTests/  Unit tests
proxy/                     Cloudflare Worker between the in-app coach and Claude (keeps the API key off the phone)
.github/workflows/         CI, TestFlight upload, signing check, coach proxy deploy
DESIGN.md                  Rules we implement, learning design, UI and architecture
```

The `Shengji/` folder is a synchronized folder in Xcode: any file you add under it becomes part of
the app automatically, so you never need to edit the project file to add sources or assets. The
Info.plist is generated from build settings, so don't add an `Info.plist` file to that folder.

## Run the core tests

The game engine, bots and learning logic live in `ShengjiCore` and run on macOS and Linux:

```sh
cd ShengjiCore && swift test
```

You can also open `ShengjiCore/Package.swift` in Xcode and press ⌘U.

## Continuous integration

`.github/workflows/ci.yml` runs on every push:

- **core-tests:** `swift test` on Linux (Swift 6.1).
- **ios-build:** builds the app for the iOS Simulator with the newest Xcode on the runner that has
  its simulator runtime installed.
- **screenshots:** installs the app in an iPhone simulator, opens every demo scene and uploads the
  pictures as the `screenshots` artifact on the run's summary page.

`testflight.yml` (run it by hand from the Actions tab) archives the app and uploads it to TestFlight,
and `check-signing.yml` checks the App Store Connect secrets it needs. `deploy-proxy.yml` tests the
coach proxy and deploys it to Cloudflare, and `diagnose-proxy.yml` sends it test requests while
showing its live logs.

## Rules and design

[DESIGN.md](DESIGN.md) is the reference for the exact rules we teach (trumps, pairs, tractors, throws,
following, scoring and levelling up), how the app teaches, the screens, and the architecture.
