# Saving, recovery and completion safety — 5.3

Implements the remaining findings from
[`WORKOUT-COMPLETION-AUDIT-2026-09-17.md`](WORKOUT-COMPLETION-AUDIT-2026-09-17.md).
Version **5.3** is set in all six shipping configurations (phone, Watch and
Live Activity, Debug/Release).

## Finishing and reviewing

- FINISH opens a native dialog with **Finish & Save**, **Discard Workout**,
  and **Keep Going**. Phone and standalone Watch save actual elapsed exercise;
  discarding is an explicit separate action. The legacy phone timer follows
  the same behavior. Confirmation actions retain the target workout ID.
- Records have an optional `endedEarly` flag. Ending before all planned work
  time has been performed—including skipping work—retains the session in
  History but does not earn a full-workout streak or milestone. Finishing
  during cooldown after all work counts normally. Older records retain their
  existing eligibility. History, detail and review label early finishes.
- Notes, type and per-interval values/notes save against the existing ID as
  they change. Repeated review appearances preserve edits. Changing type
  clears values from the previous metric before saving the new type.
- Review fields start blank instead of copying prior performances: live
  autosaving must not silently record yesterday's values as today's results.
- History shows saved performance even when a legacy series lacks the matching
  work span. Summary dismissal/Done and deletion remain idempotent.

## Phone recovery and timing

- Each phone workout receives an ID at start. TimerViewModel writes an atomic
  checkpoint to Application Support/PhoneWorkout/current.json at start,
  pause/resume, interval changes, background entry, and at most every five
  seconds during normal ticks. It includes the frozen interval plan, elapsed
  totals, recorder (including its open span), exercise type and identity.
- Relaunch restores unfinished work **paused at its last saved progress**.
  The user can resume, finish/save, discard or keep it paused. Time while the
  process was absent is not assumed to be exercise. An abrupt process loss
  can omit up to the checkpoint interval of the latest progress/samples.
- Resuming recovery restarts phone HR streaming where enabled. The Bluetooth
  connection remains independent of workout lifecycle, as before.
- Timer-setting changes rebuild only the idle/next plan. Active sessions,
  their round counts, Watch payloads and Live Activities retain the original
  plan. Settings explains that edits apply to the next workout.
- Reconciliation opens every crossed interval at its actual boundary and
  seals completion at the actual final boundary, even after a long delivery
  gap. Elapsed totals and chart spans now describe the same workout.
- Finish/discard/complete continue through the existing centralized timer,
  notification, audio, Health session and Live Activity cleanup paths.

## Durability and damaged data

- A completed checkpoint remains until both History and the series file have
  been saved. Failure displays a retry message and keeps review open. Relaunch
  retries under the original ID without duplicating the workout. A checkpoint
  with newer review edits takes precedence over an older committed row.
- Explicit deletion/discard records a tombstone before cleanup, preventing an
  old log or checkpoint from resurrecting that workout.
- Log recovery works per row and field. A damaged HR summary no longer strips
  valid breakdown/performance data from every row. The original bytes are
  archived under PhoneWorkout/Recovery before any repaired log replaces them.
  If that backup fails, the unreadable log is not overwritten.
- Invalid checkpoints are also archived before a new session may replace
  them. The UI reports actual read/write failures; it does not silently claim
  a failed completion save succeeded.
- Workout logs remain JSON in UserDefaults. Full recordings remain separate
  files; the active recovery document is not placed in the log blob.

## Watch safety

- Standalone Finish seals a completed record and uses the existing persisted
  pending queue. Its optional early-finish flag travels to phone History.
- Phone-led finish, active discard and completed delete are separate commands
  bound to a workout ID. Late finish/discard cannot delete a completion or
  affect a newer workout. Explicit completed delete removes only its target.
- Unbound legacy `cmdReset` is ignored and current state is sent back. Older
  Watch versions can still show/control the timer; finishing/deleting should
  use the phone until the Watch app updates.
- Projected completion says **TIMER FINISHED** and asks the user to check the
  iPhone; **WORKOUT SAVED** requires phone confirmation. Offline mirror Finish
  only hides the projection and explicitly directs saving to the phone.
- Imports acknowledge only a successful log + series save, an already imported
  record, or explicit discard. A failed write keeps the Watch's durable copy
  pending; phone retry/foreground also retries imports received this session.
  The committed log also prevents a duplicate Health save if an old transfer
  falls out of the bounded recent-import ID cache. The single Health saver
  remains on the phone.

## Live Activity crash found during verification

The initial UI run passed, but its diagnostic attachments contained extension
crashes in `MinimalView.body`: `Date.now...intervalEndTime` traps once the end
is in the past. All four native countdowns now use a shared non-inverted range,
with a regression covering future, exact-boundary and expired states. The
extension can safely render an old state while a finish/update is in flight.

## Verification

- Final unit run: **177 tests passed**, zero failures, including interrupted
  recovery, failed-write retry, damaged-log preservation, stale confirmation
  IDs, Watch import durability/deduplication and expired Live Activity ranges.
  Result: `/tmp/N4x4-recovery-unit-final.xcresult`.
- iPhone 17 Pro (iOS 26.5): all **9 UI tests passed** in the full run;
  four completion/recovery tests passed again after the final confirmation-ID
  and countdown changes. Results: `/tmp/N4x4-recovery-full.xcresult` and
  `/tmp/N4x4-recovery-final.xcresult`.
- iPhone SE 3 (iOS 26.5): **6 UI tests passed** for early finish + immediate
  notes, cooldown finish/History, interrupted recovery, landscape without HR,
  largest Dynamic Type, and rotation with live HR/paused timer. Result:
  `/tmp/N4x4-recovery-SE.xcresult`.
- Exported diagnostics from both follow-up UI runs contain **zero `.ips`
  crash reports**. The initial run's Live Activity crash is described above.
- Visually reviewed native finish/recovery dialogs and landscape HR layouts
  on the SE, plus controls and completion demos on the 40 mm Watch SE.
  Largest accessibility text uses scrolling to keep controls reachable.
  Design review: **8/10**; existing visual language and native dialogs are
  retained, with physical accessibility checks still pending.
- Unsigned generic-device **Release build passed**, including embedded Watch
  and Live Activity. All three built bundles report **5.3**. Log:
  `/tmp/N4x4-recovery-release.log`. `git diff --check` and project plist
  validation passed.
- Tests use unsigned simulators: HealthKit entitlement diagnostics are
  expected and do not validate actual Health writes. Xcode's final simulator
  log collection also reported the machine's CommandLineTools `simctl`
  lookup warning; all test cases and the test operation succeeded.

Remaining physical-device checks: paired Watch reachability/queued delivery,
actual Health writes and live HR sources, notification delivery and Live
Activity removal under lock, VoiceOver and haptics. These are not claimed as
verified by simulator tests. Temporary verification simulators are removed
after review; the pre-existing user simulator is left untouched.
