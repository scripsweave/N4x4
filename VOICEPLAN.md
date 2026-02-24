# Voice Prompts Implementation Plan

Users choose **Alarm / Voice Prompts / Silent** during onboarding and in Settings.
Voice mode uses `AVSpeechSynthesizer` with audio ducking (music lowers, not stops).
Three trigger points per interval: start, halfway, 30 seconds to go.

---

## Steps

- [x] **Step 1** — Create `SpeechManager.swift`
- [x] **Step 2** — Add `AudioMode` enum + `AudioPrompts` to `TimerViewModel.swift`
- [x] **Step 3** — Add `@AppStorage`, migration, prompt flags, speak methods to `TimerViewModel.swift`
- [x] **Step 4** — Wire speak calls into timer logic (`reconcileTimerState`, `startTimer`, `pause`, `reset`, `skip`)
- [x] **Step 5** — Add `.audioMode` onboarding step to `ContentView.swift`
- [x] **Step 6** — Replace alarm `Toggle` with `Picker` in `SettingsView.swift`
- [x] **Step 7** — Add `SpeechManager.swift` to `project.pbxproj`

---

## Design Summary

### AudioMode enum
```
.alarm   — existing mp3 beep, fires at interval transitions only
.voice   — AVSpeechSynthesizer, fires at start + halfway + 30s
.silent  — no audio
```

### Audio ducking
Before speaking: `AVAudioSession` → `.playback` + `.voicePrompt` mode + `.duckOthers`
After speaking finishes (delegate): restore to `.playback` + `.mixWithOthers`

### Prompt triggers
| Trigger | Condition | Content |
|---------|-----------|---------|
| Interval start | `advanced == true` in reconcile, or `startTimer()` | "[name] starting now for [X] minutes. [random start phrase]" |
| Halfway | `timeRemaining <= duration/2`, not yet fired, `duration >= 60s` | random halfway phrase |
| 30 seconds | `timeRemaining <= 30`, not yet fired, `duration > 60s` | "30 seconds to go/finish. [random 30s phrase]" |

### Prompt flags
`halfwayPromptFired` and `thirtySecondPromptFired` — reset on every interval change, reset, skip.

### Onboarding position
Step 4 of 8: Welcome → Structure → Age → **Audio Mode** → Notifications → Reminder Day → Health → Launch

### Migration (existing users)
On first launch after update: if `audioModeRaw` key absent, read `alarmEnabled` → `.alarm` or `.silent`

---

## Edge Cases
- Interval < 60s → halfway and 30s prompts skipped
- Interval exactly 60s → only halfway fires (at 30s); 30s guard requires `duration > 60`
- Last interval → 30s lead is "30 seconds to finish." not "30 seconds to go."
- Pause → `SpeechManager.shared.stopSpeaking()` called immediately
- Reset/skip → stop speech + reset flags

---

## Phrases

### Start (appended after informational line)
1. Unleash your inner Viking!
2. Odin is watching — give him a show!
3. Time to raid your limits!
4. For glory and gains, warrior!
5. Channel your inner berserker!
6. Your ancestors trained harder — now it's your turn!
7. Valhalla is earned, not given — earn it now!
8. No surrender. Only forward.
9. This is where legends are forged!
10. Pick up the hammer and charge!
11. Your VO2 max is your battle axe — sharpen it now!
12. The longship has set sail — row hard!
13. Feel the burn — that's just Odin testing you!
14. Every interval is a saga. Write a good one.
15. You chose this. Now conquer it.
16. Make Thor proud — he's watching!
17. Warriors don't hesitate — they charge!
18. The forge is hot. Strike now!
19. Your saga isn't written yet — go write it!
20. Vikings don't pace themselves — they dominate!

### Halfway
1. Halfway there, Viking — the hard part's already behind you!
2. Halfway done — Odin smiles upon you!
3. Half the battle won — finish what you started!
4. The longship is halfway home — keep rowing!
5. Your ancestors didn't stop halfway through a raid!
6. Half done! The mead hall is getting closer!
7. You're at the midpoint — stay fierce!
8. Halfway through the storm — hold your ground!
9. The finish is now closer than the start — push on!
10. Half done — your VO2 max is climbing right now!
11. Midpoint cleared — the Viking in you is just warming up!
12. Halfway through — don't waste the effort you've already put in!
13. You've made it halfway. No turning back now!
14. The sagas are written in the second half — go write yours!
15. Halfway done — your future self will thank you at the mead hall!
16. Keep going, warrior — you're on the home stretch!
17. Halfway! Valhalla gets closer with every second!
18. You've conquered half — now finish the conquest!
19. Halfway! Remember why you started — own the finish!
20. Half done — unleash everything you have left!

### 30 seconds (appended after "30 seconds to go/finish.")
1. Drain the tank completely!
2. Leave nothing on the longship!
3. 30 seconds of pure Viking glory — seize it!
4. Odin counts every one of these seconds!
5. Make these 30 seconds legendary!
6. Your ancestors didn't come this far to slow down now!
7. Unleash your final berserker fury!
8. 30 seconds to add to your saga!
9. The mead hall is 30 seconds away!
10. Prove yourself in these final 30 seconds!
11. Channel every last drop of berserker energy!
12. 30 seconds to Valhalla — go!
13. All or nothing, Viking. All or nothing!
14. Seal your legend in these last 30 seconds!
15. Pure will — that's all it takes now!
16. Finish like the warrior you are!
17. Rest is coming — earn it!
18. The raid is almost won — push through!
19. Make Odin proud in these final seconds!
20. This is your moment. Take it!
