# Analytics

Event names follow GameTimeKit's common vocabulary so dashboards can be shared across Knowlly games.
Every event carries `game=flag-trek` and `schema=<version>` (currently `1`; bump it on any breaking
change). Events contain **no personal data**: only gameplay facts, a random per-attempt id and a
random install id.

## Where events go

`FlagQuizAnalytics` sends to GameTimeKit's `AnalyticsPipeline` (built in `App/FlagTrekAnalytics.swift`),
which adds the common fields (`install_id`, `session_id`, `seq`, `ts`, `app_version`, `build`, `idiom`,
`os_major`, `lang`, `platform`), keeps a copy in `Application Support/FlagTrek/events.jsonl`, and, while
**Share anonymous usage data** is on (the default; it is in Settings), sends events to the studio's
PostHog Cloud EU project. Debug builds also write them to the device log (`LoggingAnalyticsClient`).

- The PostHog project key comes from the `POSTHOG_API_KEY` build setting in `project.yml` (empty in the
  repo, so nothing is sent until it is set).
- No analytics SDK is linked. Events are anonymous: random install id, no person profiles, no
  IP-derived location, no IDFA (so no tracking prompt). Turning the switch off stops sending at once.
- The pipeline emits `first_open`, `session_start` and `session_end` (`duration_s`, `levels_completed`);
  a session ends after 30 minutes away.

| Event | When | Properties |
|---|---|---|
| `first_open` | First ever launch (from the pipeline) | |
| `session_start` | App becomes active after more than 30 minutes away, or first launch (from the pipeline) | |
| `session_end` | Recorded when the next session starts (from the pipeline) | `duration_s`, `levels_completed` |
| `level_started` | An attempt begins | run properties* |
| `question_answered` | Each answer (wrong answers are `correct=false`) | run*, `index`, `answer`, `selected`, `correct`, `difficulty` (1 easy–3 hard), `streak`, `fuel`, `time_ms` |
| `fuel_exhausted` | Fuel hits zero | run*, `index`, `can_refuel` |
| `reward_offer_shown` | "Watch an ad to keep going" appears | run*, `placement`, `refuel_number` |
| `reward_offer_accepted` | Player taps it | same |
| `reward_offer_declined` | Player leaves without taking a shown offer | same |
| `reward_completed` | Ad watched, fuel granted | same |
| `reward_failed` | Ad cancelled/unavailable/blocked | same + `reason` (`cancelled`, `unavailable`, `ineligible_<reason>`) |
| `level_completed` | Stop or daily finished | run*, summary†, `stars` |
| `level_failed` | Ran out of fuel for good | run*, summary†, `reason=out_of_fuel` |
| `level_abandoned` | Player quit mid-run | run*, summary†, `progress` (questions answered) |
| `tutorial_started` | Tutorial opens (first launch or replay from settings) | `replay` |
| `tutorial_step` | Each tutorial answer | `replay`, `step` (0-based), `correct` |
| `tutorial_completed` | All three flags answered | `replay`, `mistakes`, `duration_s` |
| `tutorial_skipped` | Player taps Skip | `replay`, `step` (questions answered so far) |
| `hint_seen` | A one-time hint is dismissed or acted on | `hint` (`mapStart`, `stars`, `daily`) |
| `leaderboard_submit` | A counting daily score was sent to Game Center or saved to retry | `status` (`submitted`, `queued`) |
| `daily_completed` | First (counting) daily attempt recorded | `score`, `streak` |

\* run properties: `mode` (`adventure`, `daily`, `daily_practice`), `level_id`, `attempt_id`, `questions`, and for
adventure `chapter`, `stop_number`.
† summary: `score`, `correct`, `mistakes`, `best_streak`, `refuels`, `duration_s`.

Tutorial answers never produce `level_*` or `question_answered` events, so practice answers can't pollute gameplay metrics. Each tutorial run sends exactly one of `tutorial_completed` or `tutorial_skipped`.

Each attempt sends `level_started` and then **exactly one** of `level_completed`, `level_failed` or
`level_abandoned`. A retry is a new attempt (new `attempt_id`).

Useful questions this answers: where players fail (`level_failed` by `level_id`), which flags are hard
(`question_answered` accuracy by `answer`), whether look-alike distractors work (`selected` on wrong
answers), refuel conversion (`shown` → `accepted` → `completed`), and daily vs practice engagement.
