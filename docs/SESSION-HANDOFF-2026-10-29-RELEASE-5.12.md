# N4x4 5.12 release

User authorized a new App Store release on 29 October 2026. App Store Connect
confirmed 5.11 is READY_FOR_DISTRIBUTION before preparing this version. No
pending review needs replacing. Release includes all local calorie, FIT,
workout-name, bonus-round and optional voice-picker changes documented in:

- [Calories](SESSION-HANDOFF-2026-10-29-CALORIES.md)
- [FIT, names and bonus round](SESSION-HANDOFF-2026-10-29-FIT-BONUS.md)
- [Voice picker](SESSION-HANDOFF-2026-10-29-VOICES.md)

All six shipping configurations are 5.12; test-target versions remain unchanged.
What's New and detailed review notes are in `AppStore/release-notes-5.12.txt`
and `AppStore/review-notes-5.12.txt`. Existing listing, screenshots, animated
header and original physical-device Bluetooth/background-audio evidence are
to be retained. User replies remain drafts, not sent.

## Local verification

- Final voice follow-up: 285 unit tests and two focused UI tests passed.
  Previous complete regression: 280 unit tests and 24 UI tests passed.
  Result paths and visual checks are in the linked feature handoffs.
- All three generic-device Release bundles build and report 5.12:
  `/tmp/N4x4-5.12-release-build.log` (`BUILD SUCCEEDED`).
- Release tooling: six tests / 21 assertions passed. Project plist lint,
  whitespace check and case-sensitive app-icon filename checks passed.
- Garmin's official decoder validated the FIT fixtures (see FIT handoff).
- No new physical-device Watch calorie sync/Fitness display or downloaded
  voice test has been performed. Preserve those limitations; do not present
  the old review video as evidence of the new calorie feature.

## Submission

Release source is being committed and pushed for Xcode Cloud's Default
workflow. Verify its exact source commit, all four required actions and uploaded
build before running `AppStore/submit.sh 5.12 BUILD --submit`. Automatic release
after Apple approval is intended. Successful submission does not mean live.
Final Cloud and submission identifiers will be recorded after verification.
