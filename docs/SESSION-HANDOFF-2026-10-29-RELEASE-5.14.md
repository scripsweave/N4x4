# N4x4 5.14 submitted

Version **5.14 (54)** is **WAITING_FOR_REVIEW**, with automatic release
**AFTER_APPROVAL**. Submission succeeded 29 October 2026 at **15:26 CET**;
independent API verification completed at **14:27:15 UTC / 15:27 CET**.
**5.11 remains live until Apple approves this update.**

Release source/tag: **`54682f4671acab643d40ea319fe16856052c2a07` / `v5.14`**,
pushed to main and `release/5.14`. All six shipping configurations are 5.14.
[GitHub release](https://github.com/scripsweave/N4x4/releases/tag/v5.14).
Post-submission docs are on `chore/5.14-submission-handoff`; do not push docs-only
changes to main because it triggers another Cloud/App Store upload.

## Included changes

- [Apple Watch calories](SESSION-HANDOFF-2026-10-29-CALORIES.md): original
  Active Energy sample identities, durable transfer and single phone-saved
  Health workout. Pending/skip UI remains available during synchronization.
- [FIT export, workout names and optional bonus round](SESSION-HANDOFF-2026-10-29-FIT-BONUS.md).
  Bonus visibility is off by default under Settings → Intervals & Durations.
- [Installed Apple English voice picker](SESSION-HANDOFF-2026-10-29-VOICES.md)
  and preview in Settings → Audio, retaining the current default.
- AppDelegate configures playback but defers audio activation to workout or
  preview playback, following [Apple's guidance](https://developer.apple.com/documentation/avfaudio/avaudiosession).
  Existing background coaching, mixing, keepalive and alarm lifecycle remain.

Requester replies remain **unsent drafts** in `USER-REPLY-STRAVA-FIT.md` and
`USER-REPLY-VOICE-BONUS.md`. No new physical-device Watch calorie sync/Fitness
or downloaded-voice check was performed. The feature handoffs preserve those
limits; the review video demonstrates existing Bluetooth/background audio only.

## Validation

Cloud **54**, run **`d1337cb9-d336-486b-999c-66b5177d0a5b`**, passed all four
required actions: phone build, Watch build, App Store archive and iOS tests.
**309/309 test records passed**, including the earlier failed startup checks.
The exact source commit and uploaded build identity were verified before
submission. Local generic-device Release bundles all build/report 5.14:
`/tmp/N4x4-5.14-release-build.log` (BUILD SUCCEEDED).

Local startup validation passed **285 unit + seven focused Duo UI checks**:
`/tmp/N4x4-startup-validation.xcresult`. Fresh Duo simulator
`1BDA7526-9D2F-4E28-B162-810A251485ED` passed **285 unit + five UI checks**:
`/tmp/N4x4-clean-startup-validation.xcresult`. Its log reproduces the leftover
unit-test notification popup and proves setup cleared it before app launch.
Prior complete local regression passed 285 unit + 26 UI tests. Official Garmin
FIT fixture validation is recorded in the FIT handoff. Release tooling passes
six tests / 21 assertions, with project plist/whitespace/icon-case checks passing.
The known optional simulator diagnostic collection warning did not affect the
passing tests or result bundles.

Candidates 5.12 (Cloud 52) and 5.13 (Cloud 53) were never submitted. See their
handoffs for failed checks. A compact-Duo Health-status assertion now reveals
its offscreen row first; launch captures use isolated settings, verify Home is
ready and terminate between configurations. The remaining first-launch failure
was a leftover notification permission popup from unit tests. UI setup clears
that specific test-only system alert and handles a delayed notification alert;
production permission behavior is unchanged. Fresh-simulator reproduction
confirmed this correction. The GitHub 5.12/5.13 releases remain superseded drafts.

## App Store verification

- App Store version: **`1e914dc1-19c2-4cfb-92a7-b5648101f5ec`**, 5.14,
  WAITING_FOR_REVIEW / AFTER_APPROVAL.
- Selected build: **`5e18236e-0cbe-4898-a885-5a98654458da`**, 54, VALID,
  `usesNonExemptEncryption: false`.
- en-US localization: `d0c14711-b8e8-4339-a63a-60b3a447bbe9`. What's New and
  review notes match `AppStore/release-notes-5.14.txt` and
  `AppStore/review-notes-5.14.txt`.
- Review detail: `369bba7a-fea2-4f7e-b8f3-383786ffde24`. Original physical-device
  evidence attachment **`65840aee-d905-44d1-9cf6-ee81700b483b`** remains linked
  and **COMPLETE**, with checksum verified against the durable private copy at
  `~/.local/share/n4x4-review-evidence/N4x4-physical-device-review-5.12.mp4`.
- All **17** screenshot/header placements retain their source image/video IDs,
  type and group, including six Duo screenshots and the active animated
  chrome-ring header. Description, keywords, promotional text and URLs are
  unchanged. No new marketing assets were uploaded.
- The updated Apple agreement was accepted by the user before the successful
  build-start request; the agent did not accept any agreement.

`AppStore/submit.sh 5.14 54 --submit` completed successfully. A subsequent
read-only `AppStore/submit.sh 5.14 54` confirmed the exact submitted build with
no changes. The established missing-copyright-year precheck warning was
non-blocking; existing listing metadata was preserved. Submission is not
publication: the update releases automatically after Apple approves it.

Evidence and continuation helpers (private temporary files):

- `/tmp/n4x4-5.14-cloud-state.json`, `-cloud-tests.json`, `-cloud-run.json`.
- `/tmp/n4x4-5.14-submit.log`, `-final-check.log`, `-readiness.log`.
- `/tmp/n4x4-5.14-submission-verified.json`, `-media-check.json`.
- `/tmp/n4x4-5.14-cloud.rb`, `-verify-submission.rb`, `-media-check.rb`.

No further submission action or user approval is needed. Check status through
the read-only command if asked; do not repeat the upload or cancel the review.
