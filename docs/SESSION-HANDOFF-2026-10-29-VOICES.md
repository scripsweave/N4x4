# Optional Apple voice picker

Implemented locally on `feature/workout-calories`, retaining all preceding
[calorie](SESSION-HANDOFF-2026-10-29-CALORIES.md) and
[FIT/name/bonus](SESSION-HANDOFF-2026-10-29-FIT-BONUS.md) work. No push, release,
version bump or App Store submission. Shipping version remains 5.11.

## Behavior

Settings → Audio, with Voice Prompts selected, has a Spoken Voice section:

- **Voice** uses a native navigation-link picker. **Default (current voice)**
  stays selected unless changed. The empty persisted identifier retains the exact
  previous `AVSpeechSynthesisVoice(language: "en-US")` lookup, rate and pitch.
- Installed Apple English voices display their name, dialect and
  Standard/Enhanced/Premium quality. Personal Voice and third-party voices are
  excluded, so listing choices requests no permission. Cues remain English.
- **Preview Voice** speaks a short workout cue between workouts. Starting a
  workout, leaving Audio, backgrounding, changing mode or changing the voice
  stops the preview. Preview is disabled during running and paused sessions.
- `speechVoiceIdentifier` persists via AppStorage and resets to the current
  default in Reset Settings. A removed voice retains its saved identifier and
  uses the original default until reinstalled. Opening/foregrounding Audio or
  receiving `availableVoicesDidChangeNotification` refreshes the inventory.
- Download instructions point to iPhone Settings → Accessibility → Read & Speak
  → Voices → English (Spoken Content before iOS 26). Enhanced/Premium assets
  must be downloaded through Apple Settings; the app does not download them.

All existing phone speech, including zone feedback, uses the selected voice.
The Watch retains its existing haptic behavior. No actor recordings, Norwegian
translation, Siri-specific identifiers or new dependencies were introduced.

`SpeechManager` tracks utterance ownership so a late finish/cancel callback
from a replaced preview cannot restore audio over a new workout cue. Delegate
state updates run on the main queue. Stopping an already inactive preview also
restores audio when the synthesizer promises no cancellation callback. Existing
workout silent-loop keepalive and ducking choreography remain in place.

## Validation

Generic-device Release build passed for app, embedded Watch and Live Activity:
`/tmp/N4x4-voices-release.log` (`BUILD SUCCEEDED`).

Five new unit tests cover the unchanged default and fallback, persistence and
removed/reinstalled inventory, installed English voice resolution, and preview
callback ownership. Two focused UI tests cover the picker, preview, persistence
across relaunch, restoring the default, missing-voice fallback and disabling
preview in a paused workout. **285/285 unit tests and 2/2 focused UI tests
passed**, `/tmp/N4x4-voices-final.xcresult`; log:
`/tmp/N4x4-voices-final.log` (`TEST SUCCEEDED`). Initial UI assertions were
corrected to read the native picker's accessibility value rather than looking
for a separate static label; that earlier failed run is not counted.

Screenshots of the unchanged default, installed selection and unavailable-voice
fallback were visually checked under `/tmp/N4x4-voice-screens`. All fit without
clipping. Xcode's post-test simulator diagnostic collection reported a missing
`simctl` subprocess utility; the actual tests and result bundle completed
successfully. Simulator used: iPhone 17e, iOS 27.

The preceding complete regression was 280 unit tests and 24 UI tests, documented
in the FIT/bonus handoff. No physical-device Enhanced/Premium download, locked
audio or music-ducking check has been performed for this follow-up.

## Requester reply

Written in [USER-REPLY-VOICE-BONUS.md](USER-REPLY-VOICE-BONUS.md), **not sent**.
It describes the next update, current default, optional Apple voice download,
and Settings → Intervals & Durations → Show Bonus Round Button. The bonus
button appears during the last work interval and adds one recovery/work pair
before cooldown, with undo available until the added recovery starts.
