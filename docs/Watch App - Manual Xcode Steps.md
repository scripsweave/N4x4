# Apple Watch App — Manual Xcode Steps

These are the things **you** need to do by hand in Xcode before the coding agent can write any code. None of these can be scripted — they require clicking around in the Xcode UI.

Do these steps **in order**. When done, hand the project to the coding agent.

---

## Step 1 — Add the Watch App Target

1. Open `N4x4.xcodeproj` in Xcode.
2. In the menu bar: **File → New → Target…**
3. Select the **watchOS** tab at the top.
4. Choose **App** and click **Next**.
5. Fill in the form:
   - **Product Name**: `N4x4Watch`
   - **Team**: your existing team (same as the iOS app)
   - **Bundle Identifier**: Xcode will auto-fill `Jan-van-Rensburg.N4x4.watchkitapp` — leave it exactly as is
   - **Interface**: SwiftUI
   - **Life Cycle**: SwiftUI App
6. Click **Finish**.
7. Xcode will ask "Activate N4x4Watch scheme?" — click **Activate**.

You should now see an `N4x4Watch` folder appear in the project navigator.

> **Note:** On Xcode 14+, you get a single Watch App target with no separate "Extension" target inside it. That is correct. If you see a second nested target called `N4x4Watch Extension`, that is the old pattern and can happen on older Xcode — the coding agent will handle it but flag it to you.

---

## Step 2 — Set the Watch Deployment Target

1. Click on the **N4x4** project at the very top of the navigator (the blue icon).
2. Select the **N4x4Watch** target from the target list on the left.
3. Go to the **General** tab.
4. Under **Deployment Info**, set **Minimum Deployments** to **watchOS 9.0**.

---

## Step 3 — Add the Watch Complication Target (Widget Extension)

The complication (the small icon on the Watch face that launches N4x4) needs its own target.

1. **File → New → Target…**
2. Select the **watchOS** tab.
3. Choose **Widget Extension** and click **Next**.
4. Fill in:
   - **Product Name**: `N4x4Complication`
   - **Bundle Identifier**: will auto-fill as `Jan-van-Rensburg.N4x4.watchkitapp.N4x4Complication` — this is fine
   - **Include Configuration Intent**: **uncheck this box**
5. Click **Finish**.
6. When asked to activate the scheme, click **Cancel** (you don't need to run the complication separately).

---

## Step 4 — Add HealthKit Capability to the Watch App

1. Click on the **N4x4** project (blue icon, top of navigator).
2. Select the **N4x4Watch** target.
3. Go to the **Signing & Capabilities** tab.
4. Click the **+ Capability** button (top left of the tab).
5. Search for **HealthKit** and double-click it to add it.

---

## Step 5 — Add Background Modes to the iOS App

1. Still in **Signing & Capabilities**, switch to the **N4x4** (iOS) target.
2. Check if **Background Modes** is already listed. If not, click **+ Capability** and add it.
3. In the Background Modes list, check the box for **Workout processing**.

---

## Step 6 — Add Shared File Memberships

Two existing files need to compile in both the iOS app and the Watch app. You do this in the File Inspector.

### `Interval.swift`

1. In the project navigator, click on `N4x4/Interval.swift`.
2. Open the **File Inspector** panel on the right (View → Inspectors → File, or press ⌥⌘1).
3. Under **Target Membership**, you'll see a list of targets with checkboxes.
4. Check the box next to **N4x4Watch**.

### `N4x4LiveActivityAttributes.swift`

1. Click on `N4x4/N4x4LiveActivityAttributes.swift`.
2. In the **File Inspector**, under **Target Membership**, check **N4x4Watch**.

---

## Step 7 — Verify Bundle Identifiers

1. Select the **N4x4Watch** target → **General** tab.
2. Confirm the Bundle Identifier is exactly: `Jan-van-Rensburg.N4x4.watchkitapp`
3. Select the **N4x4Complication** target → **General** tab.
4. The Bundle Identifier should contain `watchkitapp` somewhere in it — Xcode sets this automatically.

---

## Step 8 — Create the Watch App Folder Structure

The coding agent will create files in an `N4x4Watch/` folder. Make sure Xcode has this group set up:

1. In the project navigator, right-click on the root `N4x4` project (or anywhere in the navigator).
2. Choose **New Group** and name it `N4x4Watch`.
3. Make sure this group is at the same level as the existing `N4x4` folder (not inside it).

> This step is optional if you're comfortable with the coding agent creating files and you adding them to the target manually afterwards. But it avoids confusion.

---

## Step 9 — Hand Off to the Coding Agent

At this point, hand the project to the coding agent with the instruction to follow `docs/Watch App - Coding Agent Plan.md`.

When the agent is done, come back here and do Step 10.

---

## Step 10 — After the Coding Agent Finishes

### Add new files to the correct targets

When the coding agent creates new `.swift` files, Xcode won't automatically assign them to the right target. For each new file the agent creates, check its target membership:

| File | Must be in target |
|---|---|
| `Shared/WatchMessage.swift` | **N4x4** and **N4x4Watch** |
| `N4x4/PhoneSessionManager.swift` | **N4x4** only |
| `N4x4Watch/N4x4WatchApp.swift` | **N4x4Watch** only |
| `N4x4Watch/WatchSessionManager.swift` | **N4x4Watch** only |
| `N4x4Watch/WatchTimerView.swift` | **N4x4Watch** only |
| `N4x4Watch/WorkoutManager.swift` | **N4x4Watch** only |
| `N4x4Watch/N4x4Complication.swift` | **N4x4Complication** only |

To check: click each file → File Inspector (⌥⌘1) → Target Membership.

### Build and fix

1. Select the **N4x4Watch** scheme in the scheme dropdown (top of Xcode, next to the play button).
2. Select an iPhone 16 simulator with a paired Apple Watch simulator as the destination.
3. Press **⌘B** to build.
4. Fix any errors. Common issues:
   - File not in the right target → add via File Inspector
   - `ActivityKit` import error on Watch → the agent should have wrapped it in `#if canImport(ActivityKit)`, verify this is in place
   - Missing `WatchConnectivity` framework → go to the Watch target → General → Frameworks, Libraries, and Embedded Content → add `WatchConnectivity.framework`

### Test on physical hardware

The HR sensor **does not work in the simulator**. For real heart rate data you need:
- iPhone (any model running iOS 17+)
- Apple Watch Series 4 or later

To run on a real Watch:
1. Connect your iPhone via cable.
2. In the destination dropdown, select your iPhone. The paired Watch will appear as a sub-destination.
3. Select the **N4x4Watch** scheme and press **▶ Run**.

---

## Quick Reference — Target Summary

| Target | What it is | Bundle ID |
|---|---|---|
| `N4x4` | The iPhone app | `Jan-van-Rensburg.N4x4` |
| `N4x4Watch` | The Watch app | `Jan-van-Rensburg.N4x4.watchkitapp` |
| `N4x4Complication` | The Watch face widget | `Jan-van-Rensburg.N4x4.watchkitapp.N4x4Complication` |
| `N4x4LiveActivity` | Dynamic Island (already exists) | `Jan-van-Rensburg.N4x4.LiveActivity` |
