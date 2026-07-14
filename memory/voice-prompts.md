# Voice Prompts Feature — Session Log

## What was built
Replaced the single `alarmEnabled` Bool with a 3-way `AudioMode` choice
(Voice Prompts / Alarm / Silent). Voice mode uses `AVSpeechSynthesizer` with
audio ducking so background music lowers while speaking, then auto-restores.

---

## Commits (chronological)

| Commit | Summary |
|--------|---------|
| `bdfbea4` | Initial implementation — all 7 steps |
| `4d0645a` | Simplify: default voice, HR cues only, fewer Viking phrases |
| `ca3adc8` | Fix default: reorder enum, fix migration logic |
| `0e23c70` | Fix HR cues to fire on every HIT and Recovery (not just first) |
| `0cd45db` | Revise prompt content and timing (halfway text, 10s warning, completion) |

---

## Files Changed

| File | Change |
|------|--------|
| `N4x4/SpeechManager.swift` | **New** — `AVSpeechSynthesizer` singleton with audio session ducking |
| `N4x4/TimerViewModel.swift` | `AudioMode` enum, `@AppStorage`, migration, prompt flags, speak methods, wired into timer |
| `N4x4/ContentView.swift` | New `.audioMode` onboarding step (step 4 of 8) |
| `N4x4/SettingsView.swift` | Alarm Toggle → segmented Picker |
| `N4x4.xcodeproj/project.pbxproj` | `SpeechManager.swift` added in all 4 locations |

---

## Current Prompt Schedule

| Trigger | Message |
|---------|---------|
| Every HIT start | "High intensity starting now for X minutes. Target heart rate: Y to Z beats per minute." |
| Every Recovery start | "Recovery starting now for X minutes. Bring your heart rate down to Y to Z beats per minute." |
| HIT halfway (duration ≥ 60s) | "Halfway through interval. [time] remaining. [Viking phrase]" |
| Recovery halfway (duration ≥ 60s) | "Halfway through recovery. [time] remaining." |
| 10s before any interval end (duration > 10s) | "10 seconds of interval remaining." |
| Workout complete | "Workout complete. Well done! [Viking phrase]" |
| Warmup | Silent (no prompts) |

---

## Key Implementation Details

### AudioMode enum (TimerViewModel.swift ~line 17)
```swift
enum AudioMode: String, CaseIterable, Identifiable {
    case voice  = "Voice Prompts"   // first = default in picker
    case alarm  = "Alarm"
    case silent = "Silent"
    var id: String { rawValue }
}
```

### @AppStorage + computed var (~line 141)
```swift
@AppStorage("audioModeRaw") private var audioModeRaw: String = AudioMode.voice.rawValue
var audioMode: AudioMode {
    get { AudioMode(rawValue: audioModeRaw) ?? .voice }
    set { audioModeRaw = newValue.rawValue }
}
```

### Migration in init() (~line 493)
```swift
// Users with alarm on (or new installs) → voice. Alarm-off users → silent.
if UserDefaults.standard.object(forKey: "audioModeRaw") == nil {
    audioMode = alarmEnabled ? .voice : .silent
}
```

### Prompt state flags (~line 452)
```swift
private var halfwayPromptFired = false
private var tenSecondPromptFired = false
```
Both reset in `resetPromptFlags()`, called from:
- `moveToNextInterval()` — interval advance via skip
- `playAlarmIfNeeded()` voice case — interval advance via reconcile
- `reset()`

### reconcileTimerState checks (~line 621)
Inside the `if now < endTime { ... }` branch (the per-tick path):
```swift
let halfwayPoint = intervals[currentIntervalIndex].duration / 2
if timeRemaining <= halfwayPoint { speakHalfway() }
if timeRemaining <= 10 && timeRemaining > 0 { speakTenSeconds() }
```

### playAlarmIfNeeded() (~line 1128)
```swift
switch audioMode {
case .alarm:  playAlarm()
case .voice:  resetPromptFlags(); speakIntervalCueIfNeeded()
case .silent: break
}
```

### speakIntervalCueIfNeeded() — fires at interval start
- `.highIntensity` → states HR target range
- `.rest` → states recovery HR target range
- `.warmup` → silent (default: break)

### speakHalfway() — fires once per interval at 50% remaining
- Guards: `duration >= 60`, `.highIntensity` or `.rest` only
- HIT: announces time + Viking phrase
- Rest: announces time only

### speakTenSeconds() — fires once per interval at ≤ 10s remaining
- Guard: `duration > 10`
- No Viking phrase

### speakWorkoutComplete() — called from finishWorkout()
- "Workout complete. Well done! [Viking phrase]"

### SpeechManager.swift — audio ducking pattern
```swift
// On speak:
try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
try? AVAudioSession.sharedInstance().setActive(true)

// On didFinish/didCancel delegate:
try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
```

### AudioPrompts enum (bottom of TimerViewModel.swift)
Two static arrays:
- `AudioPrompts.halfway` — 20 Viking halfway encouragements
- `AudioPrompts.workoutComplete` — 20 Viking completion celebrations

---

## Onboarding Step

Added `.audioMode` as step 4 of 8 in `OnboardingFlowViewModel.Step`:
```
welcome → structure → age → audioMode → notifications → reminderDay → health → launch
```
The card shows 3 tappable rows (Voice first). Tapping a row saves the choice
and auto-advances after 0.35s via `DispatchQueue.main.asyncAfter`.

---

## Settings

Replaced the old Alarm Toggle section with a segmented Picker bound to
`$viewModel.audioMode`, plus a context-sensitive subtitle describing the
selected mode. The picker order follows the enum declaration: Voice / Alarm / Silent.

---

## project.pbxproj UUIDs for SpeechManager.swift
- **fileRef**: `5739937EF07648BE8983755B`
- **buildFile**: `CC9B25853F49433F9BC51592`

---

## Bugs Fixed During This Session

### Migration defaulted new users to Alarm (not Voice)
The migration code ran `audioMode = alarmEnabled ? .alarm : .silent`. Since
`alarmEnabled` defaults to `true`, every new install got `.alarm` even though
the intent was `.voice`. Fixed to `alarmEnabled ? .voice : .silent`.

### HR cues only fired on first HIT and first Recovery
The `== 1` count guards (`highIntensityCount == 1`, `restCount == 1`) meant
intervals 2–4 were silent. Removed the guards so every HIT and Recovery
transition triggers an HR cue.

### Halfway prompt only fired for HIT, not Recovery
Initial implementation guarded `interval.type == .highIntensity`. Extended to
also handle `.rest` (with a different, Viking-phrase-free message).
