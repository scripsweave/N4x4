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
- No timer, Watch, HR arbitration, recording or Health export logic changed.
  No optional live HR chart was added. Birthday Home behavior is retained.

Main implementation commits: `2730946`, `5bd7fb4`, `3417fc5`; the final source
commit also includes the Settings accessibility refinement and media below.

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
  27.1 / macOS 27.0.1. Default workflow still archives on every main push.
- Candidate **48**, run `04bc4921-1171-4bd5-9db9-ed44c705c685`, exact source
  `3417fc5beb2115e196cdb88f1bb50dd7015e0716`: phone/Watch builds and App Store
  archive succeeded; build is VALID. Full tests still running at this handoff.
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

## Outstanding App Review evidence

Apple's Oct 2 **Guideline 2.5.4** rejection explicitly requests recordings on a
**physical iOS device** demonstrating Bluetooth HR and audible spoken workout
cues after returning to the Home Screen. No physical device appeared in the
latest `devicectl list devices`, and no existing recordings were found in the
repo/Desktop/Downloads/Movies. The user was asked asynchronously for a connected
phone/monitor or existing recordings; no response yet.

Do not fake evidence or remove the required `audio`/`bluetooth-central` modes.
`AppStore/review-notes-5.10.txt` supplies exact reviewer navigation but does not
claim recordings are attached. Checklist: `AppStore/DUO-SCREENSHOTS.md`.
Review submission `fae7a6e0-5925-4e22-9c69-17b8c6fc5af5` is still
UNRESOLVED_ISSUES. Inspect/resolve its item only after evidence is provided.

## Remaining release steps

Verify Cloud 48 full tests and the final main Cloud archive/commit, attach the
final VALID build to 5.10, then add the physical review recordings. Finish the
existing unresolved review draft deliberately; standard tooling refuses such
drafts rather than canceling them. Use the authorized submission flow in
`AppStore/SUBMISSIONS.md`, verify WAITING_FOR_REVIEW and AFTER_APPROVAL, and do
not equate a processed build or submission with public release.

Research/concepts: [Duo brief](design/iphone-duo-2026-10-24/README.md).
