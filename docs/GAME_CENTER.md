# Game Center: Daily leaderboard

The Daily Challenge has a leaderboard: everyone plays the same ten flags each UTC day, and the score of
a player's **first** attempt that day is posted. Practice rounds never post.

## One-time setup (you do this; I can't reach App Store Connect)

Steps and field names below can shift between App Store Connect versions (**verify**).

1. **Capability.** In Xcode, select the app target > Signing & Capabilities > add **Game Center**
   (or enable it on the App ID in the developer portal). The entitlement
   `com.apple.developer.game-center` is already declared in `project.yml`; it's what makes this work in
   a signed build.
2. **Create the app record** in App Store Connect with bundle id `ai.knowlly.flagquiz`
   (needed before any Game Center setup).
3. **Create the leaderboard** (App Store Connect > your app > Services > Game Center > Leaderboards):

   | Field | Value |
   |---|---|
   | Type | **Recurring** (not classic) |
   | Leaderboard ID | `ai.knowlly.flagquiz.daily` (**must match exactly**; it's `Leaderboard.dailyID` in `Leaderboard.swift`) |
   | Reference name | Daily Challenge |
   | Score format | Integer |
   | Sort order | High to low |
   | Score submission | Best score (we only ever submit one per day) |
   | Recurrence | Every **1 day**, starting at **00:00 UTC** |
   | Display name | e.g. "Daily Challenge" (localised) |

   The start time matters: the app defines a "day" as a **UTC** day, so the leaderboard's day must roll
   over at 00:00 UTC. A different start time would put scores on the wrong day's board.
4. **Test with a sandbox account.** Sign in to a Game Center sandbox account on the device or simulator
   (Settings > Game Center), install a debug or TestFlight build, finish a counting daily run, and check
   the board from the trophy button. **Verify** how long a new leaderboard takes to appear.
5. **Release.** The leaderboard has to be attached to an app version and reviewed with it.
6. **Privacy label.** Game Center adds data to the App Privacy answers (**verify** the exact entries).

If you choose a different leaderboard ID, tell me or change `Leaderboard.dailyID`.

## How it behaves

- Game Center sign-in starts **after** the tutorial and the ad-consent form, so a new player isn't met by
  a stack of dialogs. If the player isn't signed in, the game still works fully.
- Finishing a counting daily run queues the score, then sends it. If it can't go out (offline, signed
  out), it stays queued and is retried when Game Center signs in and when the app returns to the
  foreground.
- A queued score is delivered **only on the UTC day it was earned**. Afterwards it's dropped, because a
  recurring leaderboard would otherwise put yesterday's score on today's board.
- Only one score per day is ever sent, even if something upstream tried to send two.
- The result screen says whether the score was added, saved for later, or needs Game Center sign-in.
- A **trophy** button on the map (when signed in) and **View leaderboard** on the daily result screen open
  Game Center's own leaderboard UI.
- Analytics: `leaderboard_submit` with `status` `submitted` or `queued` (see `ANALYTICS.md`).

## Honest limits

- **Scores aren't verified.** The score is computed on the device, so a determined player could submit a
  fake one. That's normal for a casual game's Game Center board and is fine at launch; real protection
  would need server-side checking later.
- The daily set is identical for everyone and fully predictable from the date. That's intentional (it's
  what makes the board fair), but answers can be shared.
- Challenges, friends-only boards and achievements aren't built.

## Tested vs not tested

Tested in CI: the queue, the one-score-per-day rule, UTC day boundaries, retry and expiry
(`LeaderboardTests.swift`). **Not** tested without a real App Store Connect leaderboard and a signed-in
device: GameKit sign-in, the actual score submission, and the leaderboard screen.
