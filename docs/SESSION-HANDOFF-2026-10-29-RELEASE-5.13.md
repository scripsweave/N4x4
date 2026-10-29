# N4x4 5.13 release

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
The release source is being prepared for main/Cloud. Verify all four required
actions and the exact uploaded build before submitting through `submit.sh`.

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
