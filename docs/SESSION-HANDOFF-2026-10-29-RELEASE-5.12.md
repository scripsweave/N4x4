# N4x4 5.12 release

**Superseded release candidate:** Cloud 52 uploaded a valid binary, but its
required test action failed. The Health saved-status UI assertion did not
scroll on compact Duo; reproduced locally. The launch screenshot suite also
timed out once in Apple's accessibility snapshot machinery. The Health check
now reveals the row first, and launch captures use the shared isolated UI test
settings, verify Home is ready and terminate between configurations. All five
focused Duo checks pass: `/tmp/N4x4-5.12-duo-fixes.xcresult` (TEST SUCCEEDED).
No app behavior changed for those corrections. The fresh release is **5.13**
to avoid reusing the uploaded 5.12 number. See the 5.13 handoff for current state.
No 5.12 review submission was made; the GitHub release remains a draft.

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

- Final full 5.12 regression: **285 unit tests + 26 UI tests passed**, launch
  performance benchmark excluded. `/tmp/N4x4-5.12-full.xcresult`, log
  `/tmp/N4x4-5.12-full.log` (`TEST SUCCEEDED`, exit 0), completed 29 October
  at 12:20 CET. Tests cover the integrated calorie/FIT/bonus/voice changes and
  existing autosave/recovery, accessibility, History and export flows. Xcode's
  optional post-test simulator diagnostics reported missing `simctl`; tests
  and result-bundle generation succeeded. Feature-specific visual checks and
  earlier targeted runs are in the linked handoffs.
- All three generic-device Release bundles build and report 5.12:
  `/tmp/N4x4-5.12-release-build.log` (`BUILD SUCCEEDED`).
- Release tooling: six tests / 21 assertions passed. Project plist lint,
  whitespace check and case-sensitive app-icon filename checks passed.
- Garmin's official decoder validated the FIT fixtures (see FIT handoff).
- No new physical-device Watch calorie sync/Fitness display or downloaded
  voice test has been performed. Preserve those limitations; do not present
  the old review video as evidence of the new calorie feature.

## Submission

**Current state:** The user confirmed agreement acceptance again and Apple
accepted a build-start request at 12:33:58 UTC / 13:33 CET. Cloud **52**, run
`1e782ef8-3f97-4b0e-b1d3-a10901958f82`, is pending on the exact release source
`0655ac6a0f21d8a23c06de1b4d6cc39b233965a1`. Wait for all four required actions,
tests and uploaded build validation before submitting. No submission yet.

### Earlier agreement blocker (resolved)

**Blocked by the updated Apple Developer Program License Agreement.** Xcode's
Cloud Notices popover explicitly says the Account Holder for Jan van Rensburg
must review and accept the updated agreement before Xcode Cloud can be accessed.
The API returns HTTP 500 for otherwise valid build-start requests. No new build
run or uploaded 5.12 binary exists yet; do not claim a submitted/released update.
The user has been asked to accept at https://developer.apple.com/account/.
No agreement was accepted by the agent.

Follow-up after the user's first “done”: the native Xcode Start Build action
still returned **The PLA must be signed before builds can be created**. Safari
was signed in, but the Developer Account page still offered Review agreement
and showed only the previous agreement accepted on August 26. The exact pending
agreement `LC644S5URF` was opened at
`https://developer.apple.com/account/agree/LC644S5URF/terms`, with Agree available.
The user was asked to review and click Agree there; the agent did not click it.
At 12:21 CET, Safari still showed the pending agreement and Agree button, and
only the August 26 acceptance in the history. The full local regression passed
while waiting. **No Cloud run, 5.12 upload or review submission exists yet.**

The earlier manual-tag workflow trial had cleared the automatic/manual branch
conditions because the API replaces the condition set. All original conditions
and all four actions are now restored and compared against the pre-change
snapshot (`/tmp/n4x4-5.12-restored-workflow.json`). Main auto-start and all-branch
manual start are enabled exactly as before; no manual tag condition remains.

- Release source: `0655ac6a0f21d8a23c06de1b4d6cc39b233965a1`, pushed to main
  and `feature/workout-calories`. Annotated tag `v5.12` points to that source.
- GitHub release is a **draft**, awaiting Cloud validation and App Store
  submission. Publish/update it once the release has passed.
- App Store version: `1e914dc1-19c2-4cfb-92a7-b5648101f5ec`, 5.12,
  PREPARE_FOR_SUBMISSION, AFTER_APPROVAL.
- English localization: `d0c14711-b8e8-4339-a63a-60b3a447bbe9`. What's New
  matches the release file. Review detail: `369bba7a-fea2-4f7e-b8f3-383786ffde24`;
  detailed review notes uploaded, no demo login required.
- All **17** existing media placements were compared by source image/video
  identity, type and group against 5.11, including the six Duo screenshots and
  active animated chrome-ring header. Description, keywords, promotional text
  and URLs are unchanged. `/tmp/n4x4-5.12-media-check.json` records the check.
- The previous joined temporary review video was missing, so both original
  unabridged physical-device recordings under `tmp/` were joined again with
  AVFoundation. Duration 100.15 seconds, original portrait geometry and audio.
  Private attachment `65840aee-d905-44d1-9cf6-ee81700b483b` is **COMPLETE**.
  Durable private copy:
  `~/.local/share/n4x4-review-evidence/N4x4-physical-device-review-5.12.mp4`
  (directory 700, file 600; excluded from git). It demonstrates existing
  Bluetooth and Home Screen audio, not the new calorie feature.

## Continue Cloud validation and submission

1. Do not change/re-push main: it already contains the release source. Query
   Cloud first in case acceptance starts a queued run. Default workflow:
   `E35511FE-4DB2-4B4B-82AE-AF58FA6FEA5D`; product:
   `b9e9c87c-19b1-4458-a6be-9f7f25737f1c`. Main Git reference:
   `7c95d54a-6ba4-4d22-b524-6567f0989659`. Start Default on main if needed.
2. `/tmp/n4x4-5.12-cloud.rb` checks the exact release commit, required actions,
   test statuses and uploaded builds, writing `/tmp/n4x4-5.12-cloud-state.json`.
   It uses `/tmp/n4x4-asc.rb` for credential-backed requests without printing
   tokens. Ruby needs the existing Homebrew fastlane GEM_HOME/GEM_PATH setup.
3. Verify all four actions and the uploaded build, then run
   `AppStore/submit.sh 5.12 BUILD` followed by
   `AppStore/submit.sh 5.12 BUILD --submit`. No new release authorization is
   needed: the user already requested this release.
4. Independently verify WAITING_FOR_REVIEW/IN_REVIEW with the exact build and
   AFTER_APPROVAL. Re-run `/tmp/n4x4-5.12-media-check.rb` to confirm assets and
   COMPLETE review attachment remain intact. Publish the GitHub draft and
   record the final identifiers on the handoff branch, not main.

Automatic release after Apple approval is intended. Successful submission
does not mean live. Post-release documentation belongs on
`chore/5.12-submission-handoff`, avoiding another main-triggered upload.
