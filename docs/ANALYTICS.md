# Analytics

Event names follow GameTimeKit's common vocabulary so dashboards can be shared across Knowlly games.
Every event carries `game=flag_quiz` and `schema=<version>` (currently `1`; bump it on any breaking
change). Events contain **no personal data**: only gameplay facts and a random per-attempt id.

Until a backend is chosen, `LoggingAnalyticsClient` writes events to the device log. Swap it by
passing another `AnalyticsClient` to `AppModel`; nothing else changes.

| Event | When | Properties |
|---|---|---|
| `session_start` | App becomes active | |
| `session_end` | App goes to background | `duration_s` |
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
