# FIT export, workout names and opt-in bonus round

Later follow-up: the user authorized an installed-voice picker while explicitly
keeping the existing default. That implementation supersedes the voice
recommendation below; see [the voice handoff](SESSION-HANDOFF-2026-10-29-VOICES.md).

Implemented locally on `feature/workout-calories`, alongside the unreleased
[calorie work](SESSION-HANDOFF-2026-10-29-CALORIES.md). Nothing has been pushed or
submitted. Shipping version remains 5.11; all six version configurations are
unchanged. User authorized FIT support, naming enhancement, and a bonus-round
button hidden by default behind a setting. The voice item was a question about
Apple's options; no voice actor, voice assets or speech changes were added.

## FIT export

Saved summary and History share menus offer **Export Activity (FIT)** alongside
JSON and image sharing. The same latest-entry snapshot supplies JSON and FIT,
including review edits and custom names. File sharing reads existing local data;
it requests no extra Health permission and performs no remote upload.

`N4x4/WorkoutFITExport.swift` is a small Foundation-only encoder for FIT Activity
files (type 4), with a FIT 2.0 header, profile 21.218, header/file CRCs, file ID,
records, laps, timer events, session and activity messages. Source is identified
as N4x4 with the generic development manufacturer ID, never as a Garmin device.
The file's serial identifier derives from the saved workout UUID and its creation
time from the actual workout start, so re-export identity is stable.

- UTC timestamped HR records retain recorded measurements, quantized to FIT's
  whole-second timestamps. Session/lap elapsed and active durations use FIT's
  millisecond scale. Original pause/resume gaps become timer stop/start events.
- With a valid activity timeline, interval spans become laps with warmup,
  work, recovery and cooldown intensity. Older records without known pause
  positions use one aggregate lap with their known active duration, preserving
  the difference between elapsed and active time without inventing events.
- Existing Watch energy samples inside active segments provide calories when
  available; paused/cross-boundary and overlapping energy are not summed.
  Missing HR/calories remain absent. No GPS, distance, speed or elevation is
  fabricated from manual performance values.
- Activity comes from the chosen Type (treadmill/run, cycle, rowing, elliptical,
  stairs, otherwise HIIT). Name is stored in the session's sport profile name.
- FIT needs a recorded start/end and known active duration. Truly old rows with
  only completion date/duration keep JSON export; FIT does not invent a start.
- `.fit` is registered as `app.n4x4.fit` in Info.plist. The native Files share
  sheet preserves the FIT filename.

Strava supports FIT uploads but blocks third-party workouts from its Apple
Health import. This implements manual file export, not native account sync.
Actual Strava account acceptance is not yet verified; no account was accessed
and no workout was uploaded externally. The [requester reply draft](USER-REPLY-STRAVA-FIT.md)
is written but **not sent** and describes the next update.

## Naming and Health classification

`WorkoutLogEntry.customTitle` and `bonusRounds` are optional for old History.
Default names combine Norwegian 4×4 with the selected activity; performed bonus
work adds “+ bonus”. Names can be edited in the saved summary or History, and
History rows/FIT/JSON use the updated title.

New Health intent freezes the selected activity and a meaningful title at
completion. Health export maps the activity instead of always using HIIT, and
supplies `HKMetadataKeyWorkoutBrandName`. Apple Fitness controls the presentation
of its category headings; physical-device display remains to be verified.
Previously saved Health entries are not renamed/replaced. The editing footer
explains that names update N4x4 and exported files while a saved Health entry
keeps its original name. Invalid new optional metadata retains the existing
Health identity/status and holds new writes rather than changing a retry's type.

## Bonus round

Settings → **Intervals & Durations → Show Bonus Round Button**, off by default.
When enabled, **+1 Bonus Round** appears during the final work interval, running
or paused. It adds the original session's recovery duration and one more work
interval before cooldown, for this session only. It does not restart the current
deadline or alter next-workout settings. Only one bonus can be queued.

Undo is offered until the added recovery starts. At/after the natural boundary,
a stale tap cannot alter cooldown or another workout. A bonus can still be ended
with the existing Finish control. Extra work is tracked separately: finishing
all original work preserves completion if the bonus is abandoned, while a bonus
cannot disguise skipped original work as full completion.

The phone checkpoints the extension, elapsed bonus work and original completion
threshold. Restore retains the extended plan and resumes paused. Reactive Watch
broadcasts now observe plan changes and bonus preferences; no new manual state
broadcast calls were added. Live Activity totals, notification cues, HR spans,
performance rows and saved active time follow the actual extended plan.

Watch mirror controls use live, ID-bound commands and disable offline controls.
Standalone Watch workouts extend the shared Foundation engine, persist the plan
and import the same optional bonus metadata. A synced bonus is stripped from the
cached *next* standalone plan so it cannot accidentally become a new default.

Phone layouts reserve space for the extra control; landscape puts it alongside
Pause and Skip. Watch keeps it in the scrolling controls page. DEBUG Watch
`-demoState controls -demoBonus -demoHeartRate 0` exercises the final interval
without a phone or Health session.

## Voice recommendation (no implementation)

Apple's AVSpeechSynthesisVoice API exposes default, Enhanced and Premium voices;
the latter two need downloading. N4x4 currently requests en-US without choosing
quality. Recommend a Best Available default plus an installed-voice picker and
preview, retaining a fallback when a download is removed. Siri's own voices are
not exposed through the standard AVSpeechSynthesizer API. Availability must be
based on `speechVoices()` rather than hard-coded Siri identifiers. No VoiceOver,
Personal Voice permission or language change is needed for that future feature.

## Validation

Final full regression: **280/280 unit tests + 24/24 UI tests passed** (launch
performance skipped), including **14 new unit regressions** and **three new UI
tests**. Result: `/tmp/N4x4-enhancements-full.xcresult`; log:
`/tmp/N4x4-enhancements-full.log` (`TEST SUCCEEDED`, exit 0).

The checks cover default-off visibility/search, queued/undo behavior in portrait
and landscape, paused extension, session-duration isolation, stale commands,
checkpoint restore, standalone Watch persistence, original completion eligibility,
bonus accounting, frozen Health metadata, name persistence and FIT sharing.
Existing autosave/recovery, calorie/Health settings, large text, JSON export,
History and launch checks also pass. Initial UI checks caught a button beneath
the tab bar; both compact layouts were fixed and visually rechecked. Earlier
failed runs are not counted as passes.

Generic-device **Release build passed** for phone, embedded Watch and Live
Activity, signing disabled: `/tmp/N4x4-enhancements-release.log` (`BUILD SUCCEEDED`,
exit 0). Only the existing AppIntents metadata warnings remain. The built
Info.plist was checked for the FIT document type. `plutil -lint` and
`git diff --check` pass. No version bump, push or submission was performed.

Garmin's official Python SDK 21.218 decoded app-generated FIT fixtures with no
errors and verified CRC integrity. The paused fixture contains 90 seconds elapsed,
60 active, six HR readings, three laps with 10/35/15 active seconds, and 19 kcal
(excluding 100 kcal during a pause). A no-HR fixture retains timing and pause
events without inventing HR or calories. **2/2 fixture tests passed** with
retained FIT attachments in `/tmp/N4x4-fit-fixtures.xcresult`; these add artifact
attachments to the same tests without changing production code. The official
decoder and assertions passed again on those exact attachments. Extracted files,
validation script and report: `/tmp/n4x4-fit-validation/`; SDK lives in its
temporary venv and is not an app/repository dependency.

Visually checked phone screenshots: `/tmp/N4x4-bonus-verified` (portrait and
landscape), `/tmp/N4x4-fit-ui-verified` (share sheet and FIT Files save dialog).
The 40 mm Watch controls were inspected with the DEBUG fixture; the page scrolls
to its bonus control. Screenshot: `/tmp/N4x4-watch-bonus-final-fresh.png`.
The Watch simulator was returned to its original shutdown state afterward.

No physical Watch/iPhone was connected. Before release, verify the preserved
calorie source UUIDs and Fitness naming/classification on-device, Watch-led and
mirrored bonus commands over connectivity, and manual FIT upload to a test Strava
account. Existing JSON/image export and completed-session autosave must continue
to work.

## Primary references

- [Strava Apple Health limitation](https://support.strava.com/en-us/articles/15402024-apple-health-and-strava)
- [Strava FIT fields and uploads](https://developers.strava.com/docs/uploads/)
- [Garmin FIT protocol](https://developer.garmin.com/fit/protocol/)
- [Garmin Activity files](https://developer.garmin.com/fit/articles/cookbook/encoding_activity_files.html)
- [Garmin's profile](https://github.com/garmin/fit-python-sdk/blob/main/garmin_fit_sdk/profile.py)
- [Apple workout brand metadata](https://developer.apple.com/documentation/healthkit/hkmetadatakeyworkoutbrandname)
- [Apple speech voice quality](https://developer.apple.com/documentation/avfaudio/avspeechsynthesisvoicequality)
- [Apple on Siri voice availability](https://developer.apple.com/videos/play/wwdc2020/10022/)
