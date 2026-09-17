# Workout completion and History audit — 17 September 2026

> Historical investigation of 5.2. The subsequent implementation is documented
> in [the 5.3 recovery handoff](SESSION-HANDOFF-2026-09-17-RECOVERY.md).

Investigated shipping source **5.2, `2b8adfc`**, and compared it with the
pre-autosave source **5.0, `4a503b1`**. The client's version, exact finishing
action and History screen remain unknown. These findings establish possible
causes; they do not identify which one happened to that client.

This is an investigation, with no change to app behavior or release version.

## What explains the original report

In 5.0, reaching the completion screen did **not** write the N4x4 History
record. Only finishing the review with Done did that. The screen could show
an in-memory session that was lost if the app was terminated before Done.
Apple Health saving happened separately, so a Health record did not prove
that the N4x4 History record existed.

There were two additional access problems: the full session file was saved
only if there were at least five heart-rate samples, and History's full-detail
entry point depended on an HR summary. The calendar also exposed only one
session per day. Those issues were addressed in 5.1 and are included in 5.2:
completion writes the entry and series immediately, a list exposes every
session, and detail access no longer requires HR data. Old data that was never
written cannot be recovered merely by updating the app.

## Current path matrix

| Action or situation | What 5.2 does | What appears in phone History |
| --- | --- | --- |
| Timer reaches its final interval boundary | Saves entry and series before presenting review | One saved workout, including with no HR |
| Natural cooldown completion | Saves before the 0.8-second completion animation | Saved even before review appears |
| Skip an intermediate interval | Advances the running session | Nothing new until completion |
| Skip the final work interval with cooldown disabled | Completes and saves | One saved workout |
| Cooldown → SKIP → **End Now** | Completes and saves elapsed work, marking cooldown skipped | One saved workout |
| **END → End**, including during cooldown | Resets and discards the unfinished session | **No workout**, even when all work intervals have finished |
| Pause / minimize / change tabs / rotate | Retains the same session in memory | Nothing new until completion; no save merely from pausing |
| Lock/background, process remains alive | Runs or catches up from absolute timer anchors | Saves on completion; see interval-detail defect below |
| Phone app process ends before completion | No active-session checkpoint exists to restore | **No new workout** on relaunch |
| Change any timer duration/count or cooldown setting | Setting's `didSet` calls `reset()` | **Active session lost**, with no saved workout |
| Complete, then terminate before Done | Base workout was already saved | Saved workout survives relaunch |
| Edit type/notes/performance, then terminate before Done/dismissal | Edits remain in memory | Base workout survives; latest optional edits do not |
| Summary Done or successful swipe dismissal | Updates the same saved ID and closes the session | One workout, with review edits; no duplicate |
| Delete from summary or History | Removes entry and series; recalculates streak | Selected workout removed; other sessions remain |
| Finish while viewing another tab | Saving happens in the VM, independently of the tab | Record saved; presentation is separate from persistence |
| Watch-led natural completion / skip cooldown | Persists completed record and queues transfer until acknowledged | Appears after delivery to the phone |
| Watch-led completion → Done | Clears live engine but retains pending completed record | Sync continues; Done is not required to retain it |
| Watch-led unfinished session → END | Clears engine without creating a completed record | **No workout** |
| Watch-led completed session → Delete | Removes pending record and sends ID-bound discard | Removed, including when a late copy arrives |
| Phone-led Watch → END while reachable | Sends reset to phone | Unfinished session discarded; see command race below |
| Phone-led Watch → END while unreachable | Hides session on Watch only | Phone continues and saves if it reaches completion |
| Phone-led Watch projects past plan end while disconnected | Shows completion from its cached timeline; creates no independent record | Depends on phone actually completing and saving |
| Repeated Watch delivery | Import deduplicates by workout ID | One record; deleted imports do not return in covered tests |
| Health access denied / no HR monitor | Does not gate N4x4 completion persistence | Workout remains accessible; HR charts depend on recorded data |

## Remaining issues, ordered by user impact

### 1. END discards exercise the user may consider complete

Reproduced through the actual iPhone UI: let the work interval finish, enter
cooldown, tap END and confirm End. History is empty. The alternate
SKIP → End Now path saves the same session. The confirmation does warn that
progress will not be logged, but the two finishing actions are inconsistent.

Source: `WorkoutScreen` in `HomeWorkoutRedesign.swift`; `reset`, `skip` and
`finishWorkout` in `TimerViewModel.swift`; Watch controls follow the same
semantics. The legacy TimerView's Reset also discards unfinished work.

Recommended behavior: offer a clear **Finish & Save** action that saves actual
elapsed work, with **Discard Workout** as an explicit separate action. If
incomplete sessions are retained, distinguish them in History/streak rules
rather than implying the full protocol was completed.

### 2. Interrupted phone workouts have no recovery

Reproduced both by reconstructing the VM and by terminating/relaunching the
app during a workout. Start/end anchors, elapsed accounting and the recorder
are memory-only. Changing any of the six timer settings also resets the
active workout; all six setters were exercised. Settings UI does not protect
an active session from these edits.

Recommended behavior: checkpoint active phone sessions and their recording,
then offer resume/finish/discard after relaunch. Apply timer-setting edits to
the next workout, keeping the current workout's plan fixed.

### 3. Phone catch-up omits crossed interval spans

Reproduced a 16-second plan (5-second warmup, 4-second work, 3-second recovery,
4-second work) with timer delivery withheld across the boundaries. The saved
breakdown correctly totals 16 seconds, but the persisted series contains only
a warmup span. `reconcileTimerState` accounts for each crossed duration but
opens only the final current span; if it reaches completion it returns before
opening any crossed spans. This contradicts the existing AGENTS.md claim that
the multi-advance path records every interval.

Consequences: the workout exists, but interval cards, zone calculations and
phase coloring can be incomplete or wrong. Saved performance values whose
work spans are missing can also be inaccessible because History chooses the
series-based interval pager whenever a series file exists. Delayed completion
also uses reconciliation wall time rather than the actual final boundary.

Recommended behavior: record every crossed phase at its actual boundary and
seal the series at the real completion time. Preserve saved performance access
independently of whether a matching recorded span exists.

### 4. Review edits are not continuously saved

Reproduced: enter notes/performance after completion, reconstruct the VM
before closing review, and only the base workout is present. Dismissing the
summary saves those edits correctly. The existing "Saved to History" status
can be read as applying to all visible edits.

Recommended behavior: persist edits against the existing workout ID as they
change, with suitable debouncing for text input.

### 5. Watch completion display is not proof of phone persistence

Source-traced, not reproduced with a physical paired Watch: mirror mode
projects the phone's last timeline to completion even while disconnected.
It never produces a fallback completed record. If the phone process was
terminated, the Watch can show completion while the phone has no saved run.
Standalone mode has a persisted engine and pending-record queue, and its
engine/import tests pass; phone History still waits for actual delivery.

A related source-traced race: mirror END and completed-screen Delete both use
`cmdReset`, handled by `deleteCurrentWorkoutAndResetSession()`. An END command
arriving just after the phone completes can delete its newly saved record.
The command has neither a workout ID nor separate end/delete semantics.

Recommended behavior: recover the authoritative phone session; distinguish
projected completion from confirmed saving in Watch copy; separate finish and
delete commands and bind destructive actions to a workout ID. Keep the
existing rule that timer ownership never changes mid-workout.

### 6. Damaged persistence can hide or downgrade records

Fault-injection test: an invalid optional `hrSummary` field causes full-array
decoding to fail. The legacy fallback then re-saves the log without modern
fields such as session breakdown and performance. One malformed record can
therefore downgrade otherwise valid records in the same array. If every
fallback fails, History is shown as empty; a subsequent save can replace the
unreadable blob. There is no evidence the client's storage was corrupted.

Full-series file writes also report errors only to the console. A missing or
unreadable file leaves the History row and basic details accessible, with a
chart-unavailable message where appropriate. Watch import acknowledges the
record without checking that the file write succeeded. These write-failure
paths were inspected, not induced on physical storage.

Recommended behavior: preserve unreadable data, decode/recover records
individually, and make persistence failures observable and retryable.

## Evidence and limits

- New characterization tests cover natural completion, the cooldown display
  delay, END versus skip, lack of active-session restoration, all six timer
  setting resets, review edits, crossed-interval recording, and corrupt-log
  fallback. These describe current behavior, including defects; they are not
  assertions that the behavior is desirable.
- UI checks exercise END in cooldown, skipping cooldown followed by a swipe
  dismissal and opening History detail, and terminating an active phone run.
- Existing Watch engine/import tests exercise natural/skip completion,
  pause/resume, suspension catch-up, serialization, delayed ordering,
  deduplication, deletion and sparse/no-HR imports.
- Prior release verification already covered completed-workout relaunch
  without Done, same-day History access and deletion, rotation, and system
  activity/notification teardown. See the 5.1 and 5.2 session handoffs.
- WatchConnectivity delivery and mirrored-command timing still need a
  physical phone/Watch pair. Simulator testing cannot establish the client's
  actual path or real background delivery conditions.

Temporary audit tests and simulator are removed after investigation; the app
and shipping regression suite remain unchanged. Local test artifacts are
listed below.


### Test results

**26 targeted unit tests passed** (8 new characterization tests plus all 18
existing Watch engine/import tests). **All three UI scenarios passed**, with
one rerun after correcting the audit helper's sheet hit-testing bounds.

- `/tmp/N4x4-completion-audit-final.xcresult`: 26 units passed; END/cooldown and
  active-termination UI scenarios passed. The swipe scenario reached History
  but its helper incorrectly treated the underlying tab bar as the sheet's
  lower boundary, so that test run failed its visibility assertion.
- `/tmp/N4x4-completion-audit-ui.xcresult`: corrected swipe-to-dismiss scenario
  passed through opening the saved session detail. Screenshot attachments
  were visually checked.
- `/tmp/N4x4-completion-audit-unit.swift` and
  `/tmp/N4x4-completion-audit-ui.swift`: temporary test extensions retained
  outside the repository for reproducing the investigation.
- The first diagnostic run also exposed an overly strict floating-point
  equality assertion in the catch-up fixture. The final unit run uses a
  duration tolerance; the missing-spans finding was reproduced in both runs.

Only this report and its session-handoff link remain as repository changes.
Version 5.2 and all app/test source files are unchanged. No additional release
was pushed by this investigation.
