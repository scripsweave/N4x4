# Apple Watch calories in Apple Health exports

Implemented on `feature/workout-calories`; **not released or pushed**. Shipping
version remains 5.11 in all six configurations. The user authorized adding
calorie reporting after a support question about missing Apple Fitness calories.

## Behavior

New workouts recorded with N4x4 on Apple Watch can include Apple's Active Energy
estimate in the single phone-saved Health workout. Settings → Health & Devices →
Review Health Access requests Active Energy read and write access, separately
from Workouts and Heart Rate. Merely opening settings does not prompt. Settings
search recognizes calories, kcal, active energy and fitness.

Both phone-led and standalone Watch workouts are supported. The Watch announces
that calorie data is expected, checkpoints that expectation on disk, and sends a
final manifest of original Health sample UUIDs, numeric dates and kcal. Final
manifests use WatchConnectivity file transfer (large UUID lists can exceed
message limits) and remain queued until the phone acknowledges a durable local save.
Duplicate/older transfers cannot overwrite a final report. Foreground and
connection recovery resend pending reports; abandoned sensor reports are sealed
at their last checkpoint, without inventing energy for a crash gap.

The phone waits for both the manifest and the corresponding original Health
samples to sync. Health observer updates and the existing foreground/manual
retry paths retry pending saves. **No replacement Active Energy samples are
created.** The builder attaches the original objects, preserving source and
UUID, avoiding a second copy of the Watch's calories. The Watch and phone live
sensor builders are still discarded; `retryHealthExports()` remains the sole
workout saver.

Only whole energy samples inside recorded running segments are attached. Pauses,
recovery gaps, and samples crossing segment/start/end boundaries are excluded;
missing periods are not estimated. This is conservative and can produce partial
coverage or a slightly lower total than a Watch live cumulative number. Resting
energy is not exported. Overlapping distinct energy samples are rejected rather
than double-counted; repeated UUIDs across sensor restarts are deduplicated.

While waiting for the Watch or Health sync, History offers **Save Without
Calories**. An in-flight preflight lookup cannot overwrite that choice. Once the
energy payload has been prepared and persisted before a remote write, retries
keep it unchanged, including if permissions change. Workout saving remains
possible without energy write permission; the saved status explains the omitted
calories. Read denial is not inferred from empty query results: missing known
UUIDs remain pending and explain read access/sync, with the explicit skip option.

The Health card in the summary/History shows included kcal or why they are
missing. JSON workout export includes optional raw `energyReports` and their
units/boundary semantics, in addition to the small Health export summary.
Sharing reads existing local files. Opening settings does not prompt for permission.

Old saved Health workouts are not replaced/backfilled. Phone-only/strap-only
sessions do not invent calories. Old optional metadata stays unknown; malformed
new calorie metadata preserves the existing export identity/timing/save status
and holds new writes. History deletion/discard removes the local manifest and
ignores late transfers without deleting existing Apple Health data.

## Implementation

- `Shared/WorkoutEnergy.swift`: Foundation models, validation, atomic per-workout
  files under Application Support/WorkoutEnergy, final-report immutability,
  active-time selection/deduplication. Compiles into phone and Watch.
- Watch `WorkoutManager`: checkpoint sensor-session IDs/time boundaries, query
  existing local-device Active Energy samples, durable transfer/ack lifecycle.
  The root routes acknowledgements through `WatchSessionManager`.
- `CompletedWatchWorkout.expectsWatchEnergy` is optional for older builds. A
  report can arrive before or after the standalone completion record.
- Phone `PhoneSessionManager` routes manifests; `TimerViewModel` owns durable
  receipt, export preparation, permissions, statuses and retries. Live HR
  messages carry a small sensor-session marker to announce expected energy
  before a queued manifest arrives.
- `HealthWorkoutExport.energyContent` / `activeEnergyKilocalories` are small,
  optional fields in History. Full manifests are separate files. Original
  Health UUID/date/quantity validation happens before builder construction;
  samples are resolved again for the actual save.
- HealthKit purpose strings and Health & Devices copy explain Active Energy.

## Validation

- Final source: **266/266 unit tests + 3/3 focused UI tests passed**, including
  **14 new unit regressions** for calorie manifests, original-object identity,
  pauses/gaps, delayed delivery/Health sync, permissions, immutable retries,
  durable receipt, deletion, legacy/corrupt optional fields, standalone transfer
  order, HR expectation markers, the suspended-preflight skip race, and JSON
  export. Result: `/tmp/N4x4-calories-final.xcresult`; log:
  `/tmp/N4x4-calories-final.log` (`TEST SUCCEEDED`, exit 0).
- The preceding full regression run passed **264 unit + 21 UI tests** (launch
  performance skipped). The two later unit additions cover preflight/skip and
  JSON energy export. Result: `/tmp/N4x4-calories-full.xcresult`.
- Final focused UI checks verify new permission status without prompts, saved
  kcal and pending/skip controls in History, and largest-text settings/search.
  Screenshots were visually inspected. Saved/pending screenshots exported to
  `/tmp/N4x4-calories-history-screens`; final screenshots are also retained in
  the final result bundle.
- Phone, embedded Watch and Live Activity Simulator compilation succeeded.
  Final generic-device **Release build passed** with signing disabled:
  `/tmp/N4x4-calories-release-final.log` (`BUILD SUCCEEDED`, exit 0).
  The only Release warnings are the existing AppIntents metadata notices.
- `plutil -lint N4x4.xcodeproj/project.pbxproj` and `git diff --check` passed.
  No version bump, push, archive upload or App Store submission was performed.

## Physical-device check still required

No physical iPhone/Watch was connected. Simulator tests validate state/storage,
identity reuse, permissions policy, UI and builds, but do not prove Apple's
cross-device energy sync or Fitness rendering. Before release, on a paired
physical Watch and iPhone:

1. Allow Workouts, Heart Rate and Active Energy write access plus Active Energy
   read access. Start N4x4 on the Watch during a phone-led workout.
2. Finish after several minutes, including a pause. Confirm one Health/Fitness
   workout, the expected active duration, recorded HR, and active calories.
3. Compare Active Energy entries before/after export: the original Watch sample
   UUIDs/source should be retained and no duplicate energy entries introduced.
4. Repeat offline/standalone. Reconnect, allow Health sync time, and confirm one
   workout with calories. Check that pending status clears automatically or on
   Retry Health Save.
5. Disable Active Energy read access: known samples must remain pending, never
   be classified as read denial. Choose Save Without Calories and confirm one
   workout without calories. Re-enable access for a future workout.
6. Try write denial, delayed reconnect, Watch relaunch and explicit discard.
   Old already-saved workouts must remain unchanged.

Apple API references used:
- [Running workout sessions](https://developer.apple.com/documentation/healthkit/running-workout-sessions)
  documents automatically saved Watch energy samples and sensor calorimetry.
- [HKWorkoutBuilder](https://developer.apple.com/documentation/healthkit/hkworkoutbuilder)
  and the installed SDK `HKWorkoutBuilder.h` document adding already-saved
  samples before finishing the one workout.
- [Device sample predicates](https://developer.apple.com/documentation/healthkit/hkquery/predicateforobjects%28from%3A%29-9h87f)
  documents local-device filtering on the Watch.
