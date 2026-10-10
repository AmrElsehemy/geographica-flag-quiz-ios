# Onboarding

Principle (from GameTimeKit): **teach through play; first interaction within seconds.** There are no
instruction slides. Anything the player needs to know is shown at the moment it becomes relevant, once.

## First launch

The app opens straight into a three-flag practice round (`Tutorial`):

| Step | Flag | Coach line |
|---|---|---|
| 1 | Japan | Tap the country that matches the flag. |
| 2 | Brazil | Answer in a row to build a streak and earn bonus points. |
| 3 | USA | Last one! In real stops a wrong answer costs fuel. Here it's free. |

- Flags are iconic and easy, and no distractor looks like the answer, so nothing is ambiguous.
- Fuel is effectively unlimited, so the round can't be failed. Wrong answers show the normal feedback.
- **Skip** is always available. Skipping or finishing both mean the tutorial is not shown again.
- "How to play" in the settings menu replays it (events carry `replay=true`; state is unchanged).
- The ad-consent form waits until the tutorial is done, so a brand-new player never meets a consent
  dialog before they've played a flag.

## One-time hints (`Hint`)

At most one hint at a time, never during the tutorial, each shown once:

| Hint | Where | When |
|---|---|---|
| `mapStart` | Map card | After the tutorial, until the first stop is opened |
| `stars` | Note on the result screen | The first time a stop is completed |
| `daily` | Map card | After the first star, until the Daily Challenge is opened |

## State and tests

`OnboardingProgress` is separate from `AdventureProgress` and persisted on its own
(`UserDefaultsOnboardingStore`). Tutorial content, hint ordering and persistence are unit-tested in
`OnboardingTests.swift`; events are in [`ANALYTICS.md`](ANALYTICS.md).

## Not yet done

- Localisation (copy is English only).
- VoiceOver pass over the coach line and hint cards on a real device.
- Measuring the funnel: use `tutorial_*` events to check skip and completion rates once a backend is wired.
