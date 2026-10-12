# TestFlight

The pipeline is built: **Actions > TestFlight > Run workflow** builds a signed Release archive and
uploads it to App Store Connect. What's missing is everything that needs *your* Apple account, listed
below in order. Steps and field names in App Store Connect shift between versions (**verify**).

## What was built, and what was not tested

| Piece | State |
|---|---|
| Workflow `testflight.yml` (archive, sign through an API key, upload) | Written. **Not run end to end**: it needs your credentials. |
| "Dry run" mode (preflight + reports which secrets exist, no signing, no upload) | Safe to run any time. |
| Preflight (`Scripts/preflight-release.py`) | Tested in four scenarios (see below). |
| Release build compiles | Compiled by regular CI on every push (new). |
| Privacy manifest (`App/PrivacyInfo.xcprivacy`) | Added: the app uses `UserDefaults`, which Apple requires you to declare (**verify** the entries). |
| Export compliance (`ITSAppUsesNonExemptEncryption = NO`) | Set, so TestFlight doesn't ask on every build (**verify** it's right for you: the app only uses standard HTTPS). |
| Ads in TestFlight builds | Google **sample ads** (so testers can try the "watch an ad to keep going" button). Never earns money, never for the App Store. |
| Build numbers | Automatic: the run number, plus an optional offset. |

The preflight blocks a *production* build that has Google's sample ad ids or no ad ids, an icon with
transparency, a missing privacy manifest, a bad version number or a missing entitlement.

## Your steps, in order

1. **Apple Developer Program.** Enrol (paid, yearly) at developer.apple.com. Note your **Team ID**
   (Membership details).
2. **App Store Connect app record.** My Apps > + > New App: platform iOS, name
   **Geographica: Flag Trek**, bundle ID **`ai.knowlly.flagquiz`** (register it first under
   Certificates, Identifiers & Profiles if it isn't listed), a SKU of your choice. The name is only
   reserved now, so this is also where you learn if it's taken.
3. **Game Center** (so the daily leaderboard works in the build): follow `GAME_CENTER.md`.
4. **API key for CI.** App Store Connect > Users and Access > Integrations > App Store Connect API >
   Team Keys > +. Give it the **Admin** role (cloud signing needs it to create the distribution
   certificate; **verify** whether App Manager is enough for you). Download the `.p8` file **once**
   (you can't download it again). Note the **Key ID** and the **Issuer ID** at the top of the page.
5. **Add GitHub secrets** (repo > Settings > Secrets and variables > Actions > New repository secret):

   | Secret | Value |
   |---|---|
   | `APPLE_TEAM_ID` | Your 10-character Team ID |
   | `ASC_KEY_ID` | The API key's Key ID |
   | `ASC_ISSUER_ID` | The Issuer ID |
   | `ASC_KEY_P8_BASE64` | The `.p8` file, base64-encoded: `base64 -i AuthKey_XXXX.p8 \| pbcopy` |
   | `ADMOB_APP_ID`, `ADMOB_REWARDED_UNIT_ID` | **Only for production builds**, later. Not needed for TestFlight. |

6. **Dry run first.** Actions > TestFlight > Run workflow, tick **Dry run**. It runs the preflight
   and prints `present:` or `missing:` for each secret, without signing or uploading. Fix anything
   missing.
7. **Real run.** Run it again with Dry run off and **ads_mode = test**. It archives, signs, uploads and
   writes the build number to the run summary. Apple then processes the build (about 10 to 30
   minutes) and you get an email.
8. **Testers.**
   - **Internal** (up to 100 people in your App Store Connect team): add them under Users and Access,
     then TestFlight > Internal Testing. No review, available as soon as the build is processed.
   - **External** (public link or invited emails, up to 10,000): needs **Beta App Review** the first
     time. Have ready: a short description, contact name/email/phone, a feedback email, and the
     privacy policy URL.

## "What to test" text (paste into TestFlight)

> Thanks for testing Geographica: Flag Trek!
>
> Please try: the first-launch tutorial (and Skip), a few stops on the map, running out of fuel and
> tapping "Watch an ad to keep going" (test ads in this build), the Daily Challenge and its
> leaderboard, and turning sound/haptics off in Settings.
>
> Tell us: anything confusing in the first minute, flags that felt too easy or too hard, and any
> crashes or visual glitches (screenshots help). Which device and iOS version?

## If something goes wrong

| Symptom | Likely cause and fix |
|---|---|
| "Missing secrets" error | A secret isn't set. The error lists which. |
| "No profiles for 'ai.knowlly.flagquiz' were found" / signing errors | The bundle ID isn't registered, or the API key's role is too low. Register the ID and use an Admin key. |
| Game Center capability errors | Enable Game Center for the App ID (developer portal) and create the app record first. |
| "The bundle version must be higher" | That build number was already uploaded. Re-run with a larger **build_number_offset**. |
| Warning email about a "missing API declaration" or privacy manifest | Tell me which API it names; I'll add it to `PrivacyInfo.xcprivacy`. |
| Build stuck "Processing" > 1 hour | Usually App Store Connect. Wait, then check the status page. |
| "Invalid Binary" email | The email names the cause (often icon, missing keys, or a bad entitlement); paste it to me. |

## Before the *App Store* (not needed for TestFlight)

Create the real AdMob app and rewarded unit, add `ADMOB_APP_ID` and `ADMOB_REWARDED_UNIT_ID` as
secrets, and run with **ads_mode = production**. The preflight refuses to continue if either is
missing or still Google's sample. Then the items in `APP_STORE.md` (name check, privacy policy,
age rating, screenshots).

## Manual fallback

If CI signing gives trouble, you can archive in Xcode on a Mac (Product > Archive, then Distribute App
> App Store Connect > Upload). Set `FLAGQUIZ_ADS_MODE=test` in the build settings for a TestFlight build.
