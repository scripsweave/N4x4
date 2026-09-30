# Heart-rate samples in Apple Health workout exports

Implemented on `feature/health-workout-heart-rate` after Ian asked why his
Polar readings weren't visible as average heart rate in Apple Fitness.
Included in version 5.7 together with the Watch reliability fixes. The user
authorized release on 30 September; see SESSION-HANDOFF.md for current status.

## Behavior

- The existing single phone exporter loads the saved `HeartRateSeries`, converts
  each valid reading into a point `HKQuantitySample`, and awaits
  `HKWorkoutBuilder.addSamples` before finishing the workout. This associates
  the readings with the workout and allows HealthKit to compute statistics.
- All recorded sources use this path: Polar/other Bluetooth monitors, Watch,
  AirPods, and standalone Watch imports. The existing source arbitration still
  selects the recorded stream. No synthetic readings or calorie estimates.
- Wall-clock timestamps and gaps are preserved. Nonfinite/nonpositive readings,
  invalid/out-of-workout offsets, and duplicate offsets are omitted. The precise
  export start restores fractional seconds lost by old series-file encoding.
- Heart Rate write permission is requested alongside Workouts through existing
  user-initiated Health authorization. Viewing Health & Devices never prompts.
  The screen separately reports both write permissions and explains how to grant
  them. The iPhone Health usage string now explains the HR export.
- Without Heart Rate write access, workouts still save. History/completion shows
  that HR was omitted and links to Health & Devices for future workouts.
- Already-saved Health workouts aren't edited/replaced. An older History session
  explicitly exported as a new Health workout can include its available series.
  Finding/confirming an existing Health workout doesn't append or duplicate HR.

## Retry and compatibility rules

`HealthWorkoutExport.heartRateContent` is optional: included / noSamples /
permissionNotGranted. Old nil values mean unknown. The selection is persisted
before the first remote write and frozen across attempts. If an included export
loses write access or its series, it stays pending instead of silently dropping
HR. System permission is checked again at the write boundary.

Each sample has a stable sync identifier based on the existing workout UUID and
original sample index, version 1. The workout's existing sync identifier/version
are unchanged. Before building, and after ambiguous results, the client checks
for an existing workout identity. It returns that workout's recorded inclusion
metadata rather than guessing from current permission. Empty query results are
not proof that a record is absent; sync identifiers remain the retry safeguard.

The Watch/phone live builders still discard their workouts. The saved series
must persist before the export queue runs. Watch acknowledgements still depend
on local persistence, not Health success.

## Verification

- Xcode iOS Simulator build and **211 unit tests passed**, including eight new
  tests covering timestamps/gaps/filtering/metadata, actual Bluetooth completion,
  Watch imports, denied/not-determined HR permission, crash retry, permission
  revocation after preparation, missing series, and backward compatibility.
  `/tmp/N4x4-heart-rate-export.xcresult`.
- Both targeted UI tests passed on iPhone SE 3 (iOS 26.5): separate write
  permission status without prompts, and largest Dynamic Type/search navigation.
  `/tmp/N4x4-heart-rate-ui.xcresult`; screenshots exported under
  `/tmp/N4x4-heart-rate-ui-attachments/`.
- Project plist validation and `git diff --check` passed.
- Physical verification is still needed before shipping: grant both write
  permissions, complete a Polar workout, and check Fitness for average HR and
  the chart; retry an interrupted write and check for duplicate workouts/readings.
  Repeat without HR write permission and with a standalone Watch import.
  Simulator tests do not establish the real Fitness presentation or HealthKit's
  on-device sync-identifier handling.

Apple reference: [HKWorkoutBuilder](https://developer.apple.com/documentation/healthkit/hkworkoutbuilder).
