# iPhone Duo / 5.10 — release preparation

User authorized autonomous implementation, authentic Duo screenshots and App
Store publication. Version **5.10** is set in all six phone, Watch and Live
Activity configurations. Minimum iOS remains **17.5**.

## Implemented

- Native iOS 27.1 `ArrangementView` splits Home and Workout into related panes;
  older OS versions use local geometry. Home shows the actual plan and target
  beside Start/streak. Workout shows a large HR/target and next interval.
- Vertically stacked panes keep timer/HR above and timeline/controls below;
  active fold regions take precedence. Panes scroll independently.
- History uses `NavigationSplitView` with UUID selection preserved through
  opening, closing and rotation. Recent workouts are prominent; regular-width
  calendar/trends use a disclosure. Existing charts, intervals, sharing,
  deletion and Health recovery are reused. Toolbar actions have native symbols.
- Settings values stack below their titles at accessibility text sizes.
- Elliptical is a first-class workout type/modality with guidance and resistance-level logging. Existing Other logs remain unchanged; HR targets and effort feedback are independent of the exercise choice. Watch standalone records retain the new type through import.
- No timer, Watch, HR arbitration, recording or Health export logic changed.
  No optional live HR chart was added. Birthday Home behavior is retained.

Main implementation commits: `2730946`, `5bd7fb4`, `3417fc5`; the final source
commit also includes the Settings accessibility refinement, visible search drawer and media below.

## Verified

| Check | Result / evidence |
|---|---|
| Initial Xcode 26.6 build + tests | 243 unit + 2 UI passed, `/tmp/N4x4-duo-initial-tests.xcresult` |
| Further small-phone UI regressions | 4 passed, `/tmp/N4x4-duo-SE-ui.xcresult` |
| Xcode 27.1 unit suite | 243 passed, `/tmp/N4x4-duo-native-tests.xcresult` |
| Cloud 47 on `5bd7fb4` | Phone/Watch builds passed; 258/259 tests passed. Remaining Settings search test assumed an inline field; fixed in `3417fc5`. |
| Final native build | Succeeded, `/tmp/N4x4-duo-final-native-build.log` |
| Final Duo UI checks | **3 passed**: AX5 Settings search/diagnostics, History selection through rotation and deletion, workout rotation/paused countdown. `/tmp/N4x4-duo-final-ui.xcresult` |
| Release tooling | 4 tests / 18 assertions passed |
| Asset checks | All six shipping versions 5.10; icon filename case matches JSON; `git diff --check` passed |

Manual running/paused closed→open transitions preserved workout UUID
`28223014-6A7F-4518-880E-68BA389D9B69`; paused countdown stayed 03:20. Relaunch
recovered the same workout paused. Propped layout and portrait/landscape delete
confirmations were checked directly. History's selected Oct 24 9:00 AM session
survived close→open and returned to the same list/detail.

Local inner-display XCTest runs captured the inactive outer screen as black and
had unreliable gestures. Those failed/interrupted exploratory runs are **not**
passes. Final three tests ran successfully after restarting the dedicated
simulator in its default closed pose. Xcode's failure-diagnostic collection
still warns that default command-line tools cannot find `simctl`; the test
result itself is TEST SUCCEEDED.

## Toolchain / Cloud

Xcode **27.1 (27A9275)** installed from the App Store; user accepted the license.
iOS 27.1 and watchOS 27.0 runtimes installed. Original task-created Xcode 26.6
backup was removed after native builds succeeded to reclaim disk. Around 21 GB
free after cleanup/simulator initialization. Use `-jobs 2` for local builds.
`xcode-select -p` still points to CommandLineTools, so commands explicitly use
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

- Development workflow, no archive: `08771d11-b415-43ae-b941-2175a460f659`.
- Manual release workflow: `a09f71c6-d2f7-493b-96c2-9e28898f1a5c`.
- Both and the existing Default main-delivery workflow are pinned to Xcode
  27.1 / macOS 27.0.1. Default workflow still archives on every main push and now also requires the Duo test action.
- Candidate **48**, run `04bc4921-1171-4bd5-9db9-ed44c705c685`, exact source
  `3417fc5beb2115e196cdb88f1bb50dd7015e0716`: phone/Watch builds and App Store
  archive succeeded; build is VALID. Tests finished **258/259 passed**, again failing only Settings search. The downloaded Cloud hierarchy proves the automatic navigation search drawer was hidden, with no field or Search button. Settings now explicitly uses an always-visible navigation-bar search drawer.
  **48 predates the final Settings row refinement; use the final main build.**

Dedicated simulator: **N4x4 Duo Review**,
`E3ABFA20-EFBD-46DF-959A-53BD8A51DE8B`. It was erased once during task-specific
validation; no other devices were erased. Current display UUIDs must be read
with `simctl io UDID enumerate`, as erase invalidates previous display ports.

## App Store and media

**5.7 remains live. Nothing new has been submitted for review.** The existing
rejected 5.9 version was changed to **5.10**, retaining its listing and older
screenshots. Release and review notes were saved, automatic release selected.
Version ID `3b1854d0-a4b5-42e6-9b0c-0da2588807a1`; en-US localization
`7189c06c-d265-46fc-90e5-3a5345858024`.

All **six** Duo images are uploaded, processed with the correct exact native
specifications, placed on 5.10 en-US and ordered/verified through the new Asset
Library API. `IPHONE_DUO_PROFILE` combines inner and outer displays. Other
profiles were preserved. Raw app captures: `AppStore/raw-duo/`; opaque RGB
uploads + SHA-256/image/placement manifest: `AppStore/screenshots/duo/`.
See `AppStore/DUO-SCREENSHOTS.md`. Generated concept boards are separate and
were not uploaded as screenshots.

`AppStore/seed-duo-captures.py` seeds only the dedicated named Duo simulator,
with 27 illustrative sessions, valid interval UUIDs and corresponding HR
series. It restarts only that simulator to flush cached preferences/scenes.
Demo HR uses the existing DEBUG fixture through the real aggregator; release
builds do not enable it. No personal Health data is in the captures.

## Physical App Review evidence

Apple's Oct 2 Guideline 2.5.4 rejection requested physical-device Bluetooth HR and background-audio recordings. The user supplied both privately under untracked `tmp/`. Keep original videos out of git.

- `N4x4-physical-iPhone-demo-1.mp4`: original Bluetooth pairing, live Garmin HR and workout demonstration; privately uploaded to App Review and verified COMPLETE.
- `N4x4-physical-iPhone-demo-2.mp4`: original 40-second iPhone recording showing Home Screen icons and a spoken halfway warm-up cue at approximately 00:31. Verified using extracted frames and local audio transcription; upload/processing in progress.
- Review notes describe exactly what each video demonstrates. Neither is a Simulator recording.

Cloud **49** (`5bce09cf-1411-45c7-8727-67303559202e`, source `db5986e`) built and archived successfully, but the AX5 UI test failed while scrolling to Copy Diagnostics. Do not submit 49. The test now scrolls the actual Form collection view and allows the longer AX5 content; the assertion still requires the real button to be fully visible and hittable. Local targeted test passed: `/tmp/N4x4-elliptical-ui.xcresult` (179 seconds). All **246 unit tests passed**, including three Elliptical persistence/target/Watch-import regressions: `/tmp/N4x4-elliptical-tests.xcresult`. Release tooling: 4 tests/18 assertions passed.

Review submission `fae7a6e0-5925-4e22-9c69-17b8c6fc5af5` remains UNRESOLVED_ISSUES. Build 49 is attached provisionally; replace it with the verified final Elliptical build before resolving the rejected item.

## Remaining release steps

Verify the final main Cloud build/tests/archive and exact commit, attach the
final VALID build to 5.10, then add the physical review recordings. Finish the
existing unresolved review draft deliberately; standard tooling refuses such
drafts rather than canceling them. Use the authorized submission flow in
`AppStore/SUBMISSIONS.md`, verify WAITING_FOR_REVIEW and AFTER_APPROVAL, and do
not equate a processed build or submission with public release.

Research/concepts: [Duo brief](design/iphone-duo-2026-10-24/README.md).
