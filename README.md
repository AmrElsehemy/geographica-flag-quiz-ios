# Geographica: Flag Trek

A flag-identification adventure for iOS, and the first app in the **Geographica** family of independent geography apps.

Travel the world one continent at a time. Each stop is a handful of flags; pick the right country from four choices. Three wrong answers and you run out of fuel. Earn stars to open new stops and continents, and play the shared **Daily Challenge** (10 flags, same for everyone, with a streak).

## How it's built

| Piece | Role |
|---|---|
| [`geographica-kit`](https://github.com/AmrElsehemy/geographica-kit) | *What* geography apps know: countries, capitals, flag emoji, flag difficulty and look-alikes. |
| [`gametime-ios`](https://github.com/AmrElsehemy/gametime-ios) (GameTimeKit) | *How* games behave: haptics, synthesised audio, seeded RNG, (later) rewarded ads, analytics. |
| `Sources/FlagQuizCore` | This game's logic: adventure map, question generation, quiz session, progress, daily challenge. Pure Swift, fully unit-tested. |
| `App/` | SwiftUI app (map, quiz, results). Uses GameTimeKit's `GameTimeExperience` for feedback. |

Game rules live in `FlagQuizCore` and know nothing about UI, so they're testable on any platform.

## Run

```bash
swift test                     # game logic (works on macOS or Linux)
brew install xcodegen          # one-time
xcodegen generate              # creates FlagQuiz.xcodeproj from project.yml
open FlagQuiz.xcodeproj        # run on an iPhone 17 simulator or device
```

Set your signing team in Xcode before running on a device.

## Rewarded refuel

Run out of fuel and you can **watch an ad to keep going**, once per attempt. Everything policy-related comes from GameTimeKit (`MonetizationCoordinator`: consent, cooldown, exactly-once rewards; `GameTimeAdMob`: Google ads and the UMP consent form). This repo only decides the offer (`Refuel.swift`) and the UI.

- **Debug builds** use Google's sample ad units and sample app id, so they are always safe to tap.
- **Release builds** need real ids before shipping: replace `GADApplicationIdentifier` and set `FLAGQUIZ_REWARDED_UNIT_ID` in `project.yml`. With no unit id set, Release builds show no ads rather than a sample ad.
- Rewarded ads are never forced: the button only appears after running dry, and a missing or cancelled ad costs nothing.

## Game design

- **Stops:** 5 flags each (3–7 after merging short remainders), ordered easy → hard within a continent.
- **Fuel:** 3 per stop. Wrong answers cost 1.
- **Stars:** 3 = no mistakes, 2 = one, 1 = two. One star opens the next stop; half a continent's stars open the next continent.
- **Distractors:** easy flags get same-continent choices; hard flags get look-alikes (Romania/Chad/Andorra, Ireland/Côte d'Ivoire, …).
- **Determinism:** every stop and every day is seeded, so questions are reproducible (good for tests, replays and sharing).

## Onboarding

Teach-through-play: first launch drops straight into a three-flag guided practice round (skippable, replayable from settings, wrong answers free), then one-time hints appear in context. See [`docs/ONBOARDING.md`](docs/ONBOARDING.md).

## App Store screenshots

Captured from the real app by a UI test in debug "demo states", then captioned. Run the manual **Screenshots** workflow or `Scripts/capture-screenshots.sh`. Details in [`docs/APP_STORE.md`](docs/APP_STORE.md).

## Daily leaderboard

Game Center leaderboard for the Daily Challenge: the first attempt each UTC day posts its score; scores that can't go out are queued and retried the same day. Needs a recurring leaderboard created in App Store Connect first. Setup, behaviour and limits: [`docs/GAME_CENTER.md`](docs/GAME_CENTER.md).

## TestFlight

One-click upload through the manual **TestFlight** workflow (signing through an App Store Connect API key). Needs your Apple account, an app record and four secrets: step-by-step in [`docs/TESTFLIGHT.md`](docs/TESTFLIGHT.md). A dry-run mode checks everything except signing and upload.

## Analytics

Typed, tested events built on GameTimeKit's `AnalyticsClient`: sessions, levels, every answer, fuel exhaustion, the rewarded-refuel funnel and daily vs practice attempts. No personal data. Schema and event list: [`docs/ANALYTICS.md`](docs/ANALYTICS.md). Events currently go to the device log; plug in a backend by passing another `AnalyticsClient` to `AppModel`.

## Roadmap

1. Your Apple setup (developer account, app record, API key, secrets), then the first TestFlight build.
2. Create the Game Center leaderboard and test it with a sandbox account.
3. Real AdMob ids, final icon and screenshots.
4. More question types (capitals, name-to-flag) from the same data, once the flag mechanic is polished.
