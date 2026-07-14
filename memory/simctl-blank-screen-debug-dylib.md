---
name: simctl-blank-screen-debug-dylib
description: Why headless `simctl launch` of N4x4 shows a blank screen, and how to screenshot the UI reliably
metadata:
  type: project
---

Verifying N4x4 UI via `xcrun simctl` (screenshots, headless) has two traps that together produce a blank white/black screen even though the app runs and does not crash:

1. **Debug-dylib builds.** A normal `xcodebuild ... build` of the N4x4 scheme produces a ~58KB executor *stub*; the real code lives in `N4x4.debug.dylib` inside the `.app`. That scheme is flaky under a bare `simctl launch` (no Xcode debugger attached). Build with **`ENABLE_DEBUG_DYLIB=NO`** to get a self-contained ~9MB binary that launches cleanly. (`nm`/`strings` on the stub finding "no symbols" is a red herring, not a broken build.)

2. **Dirty simulator state.** Rapid install → terminate → launch cycling puts FrontBoard into a bad state — the log shows `FBSceneErrorDomain "Scene update failed"` / `FBWorkspaceScene "Scene create failed"` and the app renders blank. Fix: `simctl shutdown && simctl erase` the device, boot fresh, then install/launch once and wait ~10s before screenshotting.

Reliable recipe: build with `ENABLE_DEBUG_DYLIB=NO -derivedDataPath <tmp>`, erase+boot a fresh iPhone sim on the matching runtime (deployment target is iOS 17.5; runtime available was iOS 26.5), install, `defaults write <bundleid> hasCompletedOnboarding -bool true` to skip onboarding, launch, screenshot.

To screenshot the **Workout** screen headlessly (UI taps are blocked — no assistive-access for osascript, no cliclick): add a temporary `-autostart` launch-arg hook that calls `viewModel.reset(); viewModel.startTimer()` on appear, then remove it. See [[home-workout-redesign]].
