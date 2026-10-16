# App Store plan: icon, screenshots, naming

Status of each piece, then the plan. Anything marked **verify** depends on App Store Connect rules that
change; check the current requirements before submitting.

| Piece | Status |
|---|---|
| App icon (1024 px, opaque) | **Done as a first concept**: `Design/app-icon.svg`, rendered into `App/Assets.xcassets`. Needs your approval. |
| Public name and subtitle | **Approved**: Geographica: Flag Trek / A flag quiz around the world. |
| Store text (promo, description, keywords) | **Draft** below. |
| Screenshots | **Automation built** (see section 3). First run and review still to do. |
| Privacy label, age rating, support/privacy URLs | **Checklist** below. Needs decisions and URLs. |

## 1. Naming

**Approved:** the public name is **Geographica: Flag Trek**.

| Field | Value | Limit |
|---|---|---|
| App name | **Geographica: Flag Trek** (22) | 30 |
| Subtitle | **A flag quiz around the world** (28) | 30 |
| Home-screen name (`CFBundleDisplayName`) | **Flag Trek** (9) | about 12 before iOS truncates |
| Bundle id | `ai.knowlly.flagquiz` (set) | permanent once the app is created |

Why this name:
- Flag quiz names are a crowded field (many near-identical "Flag Quiz: World Flags" style titles), so the
  distinctive "Geographica" prefix is what makes the app findable.
- "Trek" is the journey across continents, which is the map. "Geographica" is the family brand, so future
  apps read as one set (Geographica: Capitals, and so on).
- "Flag" is in the name and "flag quiz" in the subtitle, which are both indexed for search, so the
  keyword list below doesn't repeat them.

Still to do (**verify**): the name is only reserved when the app record is created in App Store Connect,
and a web search can't prove a name is free. Check availability there and do a trademark search. "Trek"
is also a well-known brand word (bikes, Star Trek). Existing apps seen in search and avoided: FlagWise,
and Flaggle (a daily flag-guessing game).

The bundle id and App Store name are hard to change later. The in-app display name is easy.

## 2. App icon

**Concept:** a globe with a yellow pennant planted on it. Blue-teal gradient matches the app's own
colours. Deliberately neutral: it shows no real country's flag (a flag on the icon would favour one
country and risks looking like a different app), and it stays readable at 40 px (checked).

**Files:** `Design/app-icon.svg` (source), `Scripts/render-icon.mjs` (render), output
`App/Assets.xcassets/AppIcon.appiconset/icon-1024.png` (1024×1024, no alpha, as the App Store
requires). iOS applies the rounded corners itself, so the art stays square and full-bleed.

**Decide:**
- Keep the globe-and-pennant concept, or try alternatives (a bold single flag motif, a map pin, a
  compass)? Ask for variants if this isn't it.
- Dark and tinted icon variants (iOS 18+) are optional. **Verify** whether to supply them; without
  them iOS derives its own.

## 3. Screenshots

**Hard rule:** store screenshots must show the real app. The plan therefore captures them from the
actual build rather than mocking them up.

### Specs (**verify** in App Store Connect before final export)
- The app is iPhone-only (`TARGETED_DEVICE_FAMILY: 1`), so no iPad screenshots are needed. Revisit if
  iPad is ever enabled.
- Provide the largest iPhone size class; Apple scales down for smaller devices. At the time of writing
  that is **6.9"**: 1320×2868 (portrait). Fallback is 6.5": 1284×2778.
- 1 to 10 screenshots per size; plan **6**. The first 3 matter most (they show in search results).
- Add localised sets later when the app is localised.

### Storyboard

| # | Screen (real app state) | Caption (large, 3 to 5 words) | Why it's here |
|---|---|---|---|
| 1 | Quiz: Nepal's flag, four Asian choices, streak 3, full fuel | **Name that flag** | Core loop in one glance. Nepal's non-rectangular flag is a strong visual hook. |
| 2 | Quiz: Romania's flag, choices Romania / Chad / Andorra / Moldova | **Spot the look-alikes** | The thing that makes this harder than other flag quizzes. |
| 3 | World map: Europe partly starred, North America just unlocked | **Earn stars, unlock the world** | Shows progression and scale. |
| 4 | Daily Challenge card with a flame streak, then its result | **A new challenge every day** | Retention hook. |
| 5 | Result screen: three stars, big score | **Master 197 flags** | Reward moment, the real flag count. |
| 6 | Tutorial coach line over a flag | **Learn as you play** | Reassures new players; optional, drop it if 5 are enough. |

Don't screenshot the ad offer (it can read as an ad-driven app) or any placeholder screen.

### How to capture

Phases 2 and 3 are built. Screenshots come from the real app, not mock-ups.

1. **Demo states.** Debug builds accept `-demo-state <name>` (`App/DemoMode.swift`) and boot straight
   into a fixed state with in-memory data, no ads and no analytics:
   `quiz-nepal`, `quiz-lookalike`, `home`, `result-daily`, `result-stars`, `tutorial`. Release builds
   contain none of it.
2. **Capture.** The `FlagQuizScreenshots` UI test (`ScreenshotTests/`) launches each state, waits for
   the screen, and saves a PNG. `Scripts/capture-screenshots.sh` boots the newest iPhone Pro Max
   simulator (the 6.9" size), sets a clean 9:41 status bar and runs it.
3. **Captions.** `Scripts/frame-screenshots.mjs` puts each shot on a branded background with the
   caption from `Design/screenshots.json`, at 1320×2868. No Apple device bezels (their marketing terms
   need checking first, **verify**).

**Run it:** locally with `Scripts/capture-screenshots.sh` (macOS + Xcode + `xcodegen`), or in GitHub:
Actions tab, "Screenshots", "Run workflow". Download the `screenshots` artifact (`raw/` and `framed/`).
To change a caption or the order, edit `Design/screenshots.json`; to change what a shot shows, edit its
state in `DemoMode.swift`. Regular CI also compiles the UI test target on every push.

The same demo states can give clean gameplay footage for the planned Geographica content channel.

## 4. Store text (draft)

**Promotional text** (170 max, editable any time, 79 used):
> Guess the flag, earn stars and unlock the world. New Daily Challenge every day!

**Keywords** (100 max, comma-separated, no spaces, 94 used). The name and subtitle are indexed already,
so "flag" and "quiz" are not repeated:
> geography,countries,world,trivia,learn,brain,daily,nations,atlas,streak,guess,education,travel

**Description** (4000 max, 878 used):

```
Can you name every flag in the world?

Travel the globe one continent at a time. Each stop shows you a flag: pick the right country from four choices. Get them right to earn stars and unlock new stops, then whole new continents.

• 197 flags from every continent, in full colour
• Starts easy, gets sneaky: later stops mix in look-alike flags (Romania or Chad? Ireland or Côte d'Ivoire?)
• Three fuel per stop: a wrong answer costs one, so every guess counts
• Build streaks for bonus points
• A Daily Challenge: ten flags, the same for everyone, new every day
• Learn as you play: a quick three-flag warm-up and you're off

No ads, no account, no sign-up, and it works offline.

Perfect for geography fans, quiz lovers, travellers and curious minds of any age. How many stars can you collect?
```

Every claim above matches the code today (197 flags, look-alike distractors, 3 fuel, streak bonus, daily
set, no ads, no account, offline play). Re-check this list before each release.
If ads, a Game Center leaderboard or any purchase ships, add them here.

**Category:** primary Games › Trivia; secondary Games › Educational (**verify** available subcategories).

## 5. Compliance checklist (all **verify**)

- **Privacy policy URL and support URL:** both required. Not created yet. The Knowlly Games web repo
  (`gametime-web`) is the natural home.
- **Privacy "nutrition label":** 1.0 has no ad or analytics SDKs and analytics events are device-log
  only, so "Data Not Collected" should apply (**verify**, including Game Center). Update the label when
  ads or a real analytics backend are added.
- **Consent / tracking:** nothing to do for 1.0 (no ads, no tracking). Revisit when ads return.
- **Age rating:** answer the questionnaire; expect a low rating. Do **not** tick "Made for Kids":
  that changes the allowed ads and analytics.
- **Territories and country list:** the quiz includes Taiwan, Palestine and Kosovo. Some storefronts
  (notably mainland China) are sensitive about how Taiwan and similar entities are presented. Decide the
  country list and which storefronts to release in before submitting. This is a product decision, not a
  technical one.
- **Flag artwork:** public-domain source (see the kit's `ATTRIBUTION.md`); some flags include state
  emblems. Fine for in-app use; keep marketing material to ordinary flags if in doubt.
- **Ads:** none in 1.0; the app links no ad SDK.

## 6. Order of work

1. You approve or redirect: icon concept (the name is approved).
2. Create the App Store Connect record (bundle id, name, categories) and the privacy/support URLs.
3. Run the "Screenshots" workflow, review the set, adjust captions and states.
4. Upload with the TestFlight build (see `TESTFLIGHT.md`).

## 7. Open questions

1. Is the globe-and-pennant icon the right direction? Alternatives on request.
2. Which storefronts and what country list for launch (see the Taiwan/Palestine/Kosovo note)?
3. Where will the privacy policy and support pages live?
