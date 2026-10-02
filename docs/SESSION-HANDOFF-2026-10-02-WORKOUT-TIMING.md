# Active workout timing — 5.9

Louise reported 924 minutes of exercise on October 2. Her Health screenshot
shows one N4x4/iPhone HIIT workout from September 30 at 15:32:44 to October 2
at 15:24:29, lasting 47h 51m 45.85s. Today's reported exercise minutes match
midnight to 15:24. Her exact interaction sequence and incident version are
unknown; a recovered old session is a demonstrated route to this defect.
The earlier missing-workout reports are not conclusively explained by this.

## Changes

- The shared Foundation `WorkoutActivityTiming` stores numeric wall-clock
  running stretches, preserving subsecond precision through Watch ISO-date
  transfers. Pause/resume and completion are recorded on phone and standalone
  Watch. Continuous adjacent stretches merge, keeping stored data small.
- Phone checkpoints close a copy at the last saved progress. Relaunch restores
  it paused; absent process time never becomes exercise. An old checkpoint can
  recover a known continuous stretch only when its start/progress timestamps
  agree with recorded active duration. Otherwise timing remains unknown.
- Completed Watch transfers, series files and Health export intent carry the
  optional timing. Older files still decode. Health exports freeze this data
  alongside their existing stable identity and heart-rate payload policy.
- The Health builder receives pause/resume events, including a trailing pause
  when a standalone workout is finished while paused. Original wall-clock
  timestamps and HR sample gaps remain intact.
- Before saving, validate active time against recorded History duration and
  HealthKit's calculated builder duration. Inconsistent older pending exports
  remain in History with an explanatory error; their immutable payload is not
  silently rewritten. A known legacy series with unexplained gaps cannot fall
  back to an invented continuous timeline. Already-saved Health workouts are
  never automatically replaced or repaired.
- `startTimer` rebuilds the absolute interval deadline whenever the previous
  state was paused. This fixes Watch resume, which previously called that entry
  point directly and could count the pause as interval progress or finish early.

## Validation

The simulator regression uses a 10-minute session recovered across a
47h 51m 45.85s wall-clock span. HealthKit's own `HKWorkout` event-based duration
calculation returns 600 seconds. Tests also cover Watch resume, repeated
recovery/pauses, finish while paused, a fresh subsequent workout, immutable
retries with unchanged HR timestamps, old pending exports, old checkpoints,
standalone Watch serialization/import, trailing pauses, and invalid timelines.

Final test/build results and release identifiers are recorded in
`SESSION-HANDOFF.md` once verified. No physical devices were connected; actual
Health database writes, Fitness ring recalculation and paired-radio behavior
still require physical-device validation. Simulator tests inject the Health
save boundary; the event-duration assertion uses the real HealthKit model.
