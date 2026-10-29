# N4x4 5.13 release

**Superseded candidate:** Cloud 53 passed 308/309 test records, including both
corrected checks, but the first bonus UI test failed before launch obtained a
process ID. Its trace shows a notification permission popup left by unit tests
interrupting startup. The UI setup now clears that known test-only system popup
before launch and handles delayed notification alerts. A brand-new Duo simulator
reproduced the popup, cleared it and passed the bonus check. App startup audio
activation is also deferred to workout/preview playback per Apple's guidance.
The next candidate is **5.14**; no 5.13 review submission occurred.

The user authorized App Store release of the calorie, FIT, workout-name,
bonus-round and optional voice-picker changes. Apple accepted the updated
Developer Program agreement; the agent did not accept it. Version 5.11 is live.

The 5.12 candidate (Cloud 52, source `0655ac6`) uploaded successfully but failed
two required UI checks: a compact Duo assertion before scrolling to the saved
Health status row, and a launch accessibility snapshot timeout. The former was
reproduced on local Duo and corrected by revealing the row first. Launch capture
setup now uses the existing isolated settings and verifies Home is ready;
captures terminate between configurations. App behavior is unchanged.

All five focused Duo checks pass in `/tmp/N4x4-5.12-duo-fixes.xcresult` (log of
the same stem, TEST SUCCEEDED). The prior complete local regression passed
285 unit and 26 UI tests. No physical-device calorie sync test was performed;
limitations in the [calorie handoff](SESSION-HANDOFF-2026-10-29-CALORIES.md) remain.

Fresh version **5.13** avoids reusing the uploaded candidate's number. All six
shipping configurations are 5.13; no test-target version change. Release/review
notes are in `AppStore/release-notes-5.13.txt` and `AppStore/review-notes-5.13.txt`.
Release source/tag **`bd6b1289d01c7e77cd583d2ed3279591a6c3653a` / `v5.13`**
is pushed to main and `release/5.13`. Cloud **53** started automatically after
the push; run **`77e97d16-2c17-41c5-a6df-8fcb5736a1b9`**. Phone, Watch and
archive actions have passed. The required test action is still running at
13:26 UTC. Uploaded App Store build **`2a8a8b3a-8d6d-40a0-9c85-4e2d6c8c14fe`**
is VALID (5.13 / 53). Read-only `AppStore/submit.sh 5.13 53` passed; log
`/tmp/n4x4-5.13-readiness.log`. **Do not submit until the test action passes.**
No further user approval is required. No App Store submission yet.
The GitHub 5.13 release is a draft; 5.12 is marked a superseded draft.

Local helper `/tmp/n4x4-5.13-cloud.rb` verifies source identity, actions, tests
and uploaded builds, writing `/tmp/n4x4-5.13-cloud-state.json`. Media verification
is `/tmp/n4x4-5.13-media-check.rb`; final submission verification is
`/tmp/n4x4-5.13-verify-submission.rb`. The Homebrew Ruby/fastlane GEM_HOME and
GEM_PATH setup is the same as the 5.12 helper scripts. Submit the exact validated
build via `AppStore/submit.sh 5.13 53 --submit` only after all required actions
and test results pass. Release authorization is already given; do not ask again.
Do not push another docs-only change to main.

All three generic-device Release bundles build and report 5.13:
`/tmp/N4x4-5.13-release-build.log` (BUILD SUCCEEDED). Release tooling's six tests
and 21 assertions pass; plist/whitespace checks pass.

The editable 5.12 App Store draft is renamed to 5.13, preserving the same
version/localization/review identifiers and all 17 media placements:

- Version `1e914dc1-19c2-4cfb-92a7-b5648101f5ec`.
- en-US `d0c14711-b8e8-4339-a63a-60b3a447bbe9`.
- Review detail `369bba7a-fea2-4f7e-b8f3-383786ffde24`.
- COMPLETE original-recording attachment `65840aee-d905-44d1-9cf6-ee81700b483b`.

Retain existing listing/screenshots/header/video, AFTER_APPROVAL, ratings, and
no phased release. User replies remain unsent drafts. Post-submission docs must
stay off main until another shipping version bump.
