# Geographica: Flags Adventure

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
brew install xcodegen
xcodegen generate              # creates FlagQuiz.xcodeproj from project.yml
open FlagQuiz.xcodeproj        # run on an iPhone 17 simulator or device
```

Set your signing team in Xcode before running on a device. The bundle id (`games.knowlly.geographica.flagquiz`) is a placeholder.

## Game design

- **Stops:** 5 flags each (3–7 after merging short remainders), ordered easy → hard within a continent.
- **Fuel:** 3 per stop. Wrong answers cost 1.
- **Stars:** 3 = no mistakes, 2 = one, 1 = two. One star opens the next stop; half a continent's stars open the next continent.
- **Distractors:** easy flags get same-continent choices; hard flags get look-alikes (Romania/Chad/Andorra, Ireland/Côte d'Ivoire, …).
- **Determinism:** every stop and every day is seeded, so questions are reproducible (good for tests, replays and sharing).

## Roadmap

1. Rewarded "refuel" continue via GameTimeKit's monetisation coordinator (`QuizSession.refuel()` is already in place).
2. Analytics events and Game Center leaderboard for the daily challenge.
3. Real flag artwork (SVG) instead of emoji, which also unlocks "Paint the Flag".
4. Capitals and country-name-to-flag question types from the same data.
