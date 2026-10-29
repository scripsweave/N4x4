# N4x4 5.14 release

The user authorized release of the calorie, FIT, workout-name, bonus-round and
voice-picker features and confirmed acceptance of Apple's updated agreement.
No further release approval is needed. Version 5.11 remains live.

Candidates 5.12 (Cloud 52) and 5.13 (Cloud 53) uploaded valid binaries but were
not submitted because required UI checks failed. See their handoffs. The
compact Duo status-row check now scrolls first, and launch captures use isolated
settings. Cloud 53 passed those corrections and 308/309 test records overall;
its sole failure was the first UI launch failing to obtain a process ID.

Cloud 53's activity trace shows a leftover **notification permission alert**
from unit tests interfering with launch. The UI test setup now clears only
that specific test-system alert before launch and registers an interruption
handler for a delayed notification alert. Five seconds are allowed for the
asynchronous alert to appear. Production notification permission behavior is
unchanged. A fresh Duo simulator reproduced the popup and the helper tapped
Allow before the first UI launch; the bonus test then passed.

`AppDelegate` no longer activates audio on idle launch. Playback category/mixing
configuration remains. `SpeechManager` already activates on workout start/resume
and voice preview, preserving coaching, keepalive and alarm playback. Apple
[recommends deferring activation until playback](https://developer.apple.com/documentation/avfaudio/avaudiosession).

Validation:

- 285 unit tests + seven focused Duo UI checks pass with the startup change:
  `/tmp/N4x4-startup-validation.xcresult` (TEST SUCCEEDED).
- Fresh simulator `1BDA7526-9D2F-4E28-B162-810A251485ED`, N4x4 Clean Release QA:
  `/tmp/N4x4-clean-startup-validation.xcresult` (TEST EXECUTE SUCCEEDED). All
  285 unit tests and five UI checks passed, including four launch captures.
  Logs prove the
  leftover notification alert was reproduced and cleared before app launch.
- Prior complete local regression: 285 unit + 26 UI tests passed.
- No physical-device calorie sync/Fitness or downloaded-voice check has been
  performed. Feature handoffs retain the limits; no new physical evidence is
  claimed. Existing review video demonstrates Bluetooth/background audio only.

All six shipping configurations are **5.14**, avoiding reuse of uploaded 5.13.
Release/review notes are in `AppStore/release-notes-5.14.txt` and
`AppStore/review-notes-5.14.txt`. Generic-device Release build passed for app,
embedded Watch and Live Activity; all bundles report 5.14. Log:
`/tmp/N4x4-5.14-release-build.log`. Release tooling: six tests / 21 assertions
pass, with plist lint and whitespace checks passing.
Prepare/push the final release source and tag, verify all four Cloud actions
and the exact uploaded build, then use `AppStore/submit.sh 5.14 BUILD --submit`.
Do not stop to request another confirmation; the user already authorized release.

Rename the editable App Store draft to 5.14, preserving all 17 media placements,
listing, header and processed private review video. Stable identifiers:

- Version `1e914dc1-19c2-4cfb-92a7-b5648101f5ec`.
- en-US `d0c14711-b8e8-4339-a63a-60b3a447bbe9`.
- Review detail `369bba7a-fea2-4f7e-b8f3-383786ffde24`.
- COMPLETE attachment `65840aee-d905-44d1-9cf6-ee81700b483b`.

Keep AFTER_APPROVAL, no phased release and existing ratings. Replies remain
unsent drafts. Publish the GitHub release only after validation/submission;
keep superseded 5.12/5.13 GitHub releases as drafts. Post-submission docs go on
a handoff branch, not main (main pushes trigger Cloud/App Store uploads).
