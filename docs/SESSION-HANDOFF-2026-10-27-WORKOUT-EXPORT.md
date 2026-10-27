# Complete workout export

Requested by Hristo Marinov on 27 October: export all stages and available
workout data for AI analysis instead of taking screenshots.

Branch: `feature/full-workout-export`. User authorized App Store release on
27 October. Version **5.11** is prepared in all six shipping configurations;
release notes are in `AppStore/release-notes-5.11.txt`. Cloud validation and
submission are pending.

## Reply draft (not sent)

Hi Hristo,

Thanks for the feedback—and for explaining how you're using the data. A
complete export would make that much easier.

I'm adding an “Export Workout” option with all recorded stages, heart-rate
samples, interval statistics, performance values, and notes in a single JSON
file you can upload for AI analysis.

Thanks for the suggestion!
Jan

## Behavior

Open a completed workout or a History session, tap Share, then **Export Workout
(JSON)**. The native share sheet can save the file or pass it to another app.
**Share Image** remains available when a chart exists. Older entries without
a recording can still export their saved fields.

`N4x4/WorkoutExport.swift` defines the Transferable snapshot and versioned,
pretty-printed JSON document (`format: app.n4x4.workout`, `schemaVersion: 1`):

- `workout`: the full saved `WorkoutLogEntry`, including breakdown, notes,
  all performance rows (including unmatched rows/secondary values), summary,
  early-ending flag and any saved Health export metadata.
- `recording`: the entire saved `HeartRateSeries`, without further
  downsampling: original sample offsets/BPM, interval spans/targets and
  activity timing. Missing recordings are omitted and marked unavailable.
- `stages`: recorded stage order, absolute dates, wall-clock duration,
  active duration when valid timing exists, sample count, average/peak BPM,
  in-zone percentage and time to zone using the existing interval-card rules.
- `performanceMetric`, `definitions`, `recordingStatus`: explicit units,
  sampling/timing conventions, unavailable-data semantics and statistic rules.
- Export date, app version/build and schema version.

Dates use ISO 8601 UTC with milliseconds. Numeric original timing timestamps,
sample offsets and values retain their precision. Speed stays canonical km/h.
Pauses/recovery gaps are preserved. Legacy active time and missing stages are
never inferred from wall-clock duration or today's settings. Only locally
stored data is exported; no new Health queries, permission prompts or writes.

`TimerViewModel.workoutExport(for:series:)` resolves the current autosaved row
by UUID and uses the completed in-memory series for the current review.
Exporting does not complete/reset the review or create another History row.
`WorkoutShareMenu` is shared by both detail presentations. CoreTransferable
encodes on demand; it does not keep permanent temporary export files.

## Validation

- Xcode 27.1 phone/embedded Watch/Live Activity Simulator builds succeeded.
- **8/8 targeted tests passed**: five serialization/statistics/legacy/timing
  tests, one ViewModel test for current review edits/canonical units/deletion,
  and two UI tests. The full-record test round-trips both original saved
  models, including fractional values, every sample/span, unmatched performance
  notes, Health metadata and activity timing.
- UI checks on **N4x4 Export Review** (iPhone 17e, iOS 27.0,
  `7D6306A8-1295-4303-AED8-3F01DBD1DAC5`) verify the summary export, export of
  the same session from History after relaunch (exactly one saved workout),
  image sharing still present, export without a recording/image, and the native
  Files **Save** dialog. Screenshots are retained in the result bundle.
- Final result: `/tmp/N4x4-workout-export-passing-tests.xcresult`;
  log: `/tmp/N4x4-workout-export-passing-tests.log` (`TEST SUCCEEDED`, exit 0).
- `plutil -lint N4x4.xcodeproj/project.pbxproj` and `git diff --check` passed.

Earlier exploratory UI runs failed on native share-sheet selectors and
dismissal/cleanup assumptions. These are not counted as passes. The final
regression checks relaunch between summary and History and opens Files instead
of testing system popover/cancel behavior. Actual delivery to an external AI
app and physical-device sharing have not been exercised. No sensor, timer,
Health export, workout persistence or Watch protocol behavior changed.
