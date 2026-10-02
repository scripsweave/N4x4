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

Final validation: **243 unit tests and 5 UI tests passed** in
`/tmp/N4x4-5.9-final-tests.xcresult`. The five UI tests cover recovery, paused
rotation, early finish/review persistence, cooldown finish/History, and pending
versus confirmed Health saves. Generic-device Release build passed for all
three shipping targets (`/tmp/N4x4-5.9-release-final.log`); all bundles report
5.9. Exported simulator diagnostics contained no `.ips` files. Release tooling
checks passed (4 tests / 18 assertions), as did project plist validation and
`git diff --check`.

No physical devices were connected; actual
Health database writes, Fitness ring recalculation and paired-radio behavior
still require physical-device validation. Simulator tests inject the Health
save boundary; the event-duration assertion uses the real HealthKit model.

## Release

Release commit `358a46fff22866836ddd250c01de6ae3ebe6f958`, tag `v5.9`.
[GitHub release](https://github.com/scripsweave/N4x4/releases/tag/v5.9).
Xcode Cloud build **45**, run `48df1e4d-71b3-43a1-80d6-ec1f1bb80d0e`, passed
Build - iOS, Build - watchOS and Archive - iOS for that exact commit.

The user authorized fixing, testing and releasing a new version. Because 5.8
(44) was still waiting for review, its exact submission
`1035297b-d29b-447b-b284-cd6812d6153b` was canceled after verifying 5.9 (45) was
VALID. The operation checked the app, version, old build and single review item.
Once Developer Rejected, version record `3b1854d0-a4b5-42e6-9b0c-0da2588807a1`
was changed to 5.9, preserving the listing and screenshots.

`AppStore/submit.sh 5.9 45` passed read-only preflight, then the authorized
`--submit` run attached build 45 and verified **WAITING_FOR_REVIEW** with
**AFTER_APPROVAL** at 22:38 CEST on October 2. Apple approval is still pending;
5.7 remains live. The existing missing-copyright-year precheck warning was
non-blocking. Submission log: `/tmp/N4x4-5.9-submission.log`.

Post-submission documentation is on `chore/5.9-submission-handoff`; do not push
another main commit with the already-uploaded 5.9 marketing version.
