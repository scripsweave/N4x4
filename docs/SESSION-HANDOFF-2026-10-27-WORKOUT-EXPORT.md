# Complete workout export

Requested by Hristo Marinov on 27 October: export all stages and available
workout data for AI analysis instead of taking screenshots.

Version **5.11 (51)** is **WAITING_FOR_REVIEW**, with automatic release
**AFTER_APPROVAL**, verified 27 October at **19:10 CET / 18:10 UTC**. User
authorized release after implementation on `feature/full-workout-export`.
All six shipping configurations are 5.11. Release source/tag is
`ea361a306fda3080fa74acad4dba8170d16cf6aa` / `v5.11`, pushed to main.
Cloud **51** passed all four required actions and **270/270 tests** for that
exact commit. **5.10 remains live pending Apple approval of 5.11.**

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

## App Store release

- User authorized release on 27 October. Apple confirmed **5.10 is live**
  before creating the new 5.11 draft; no pending review was canceled.
- Generic-device Release build passed for phone, embedded Watch and Live
  Activity; all three built bundles report 5.11. Log:
  `/tmp/N4x4-5.11-release-build.log`.
- Release tooling: **4 tests / 18 assertions passed**. All six shipping
  configurations match, and the tracked app icon filename matches its JSON
  by case.
- Exact Cloud run **51**: `2e40f5c5-cb3f-4e2c-b341-e8d65f112954`.
  All four required actions passed: phone build, Watch build, App Store archive
  and **270/270 tests** (252 unit + 18 UI), including all eight new export tests.
  Uploaded App Store build `90b76d31-8dbc-49bc-94fb-458bedcae3e7` is VALID.
- Release tag `v5.11` points at the exact validated source commit.
  [GitHub release](https://github.com/scripsweave/N4x4/releases/tag/v5.11).
- App Store version `8e70f1c4-f2ad-49a2-8fe3-967dd604e324` (5.11) is
  WAITING_FOR_REVIEW with AFTER_APPROVAL selected. English localization:
  `690ce5f9-1b23-4829-af5d-5a993eb33c3e`. Release/review notes are uploaded.
- All **17** existing screenshot/header placements were inherited and compared
  against 5.10 by media identity/group/type, including six Duo screenshots
  and the animated chrome-ring header. No new marketing assets were uploaded.
- The original private physical-device evidence was checked against the
  previously approved attachment's checksum and file size, then attached to
  the new version. Final attachment: `6583b335-a12d-41d1-ad09-635190fb3729`,
  `N4x4-physical-device-review.mp4`. Processing is COMPLETE; the review notes
  identify the Bluetooth and Home Screen audio segments. Videos remain outside
  git.
- Post-submission documentation and release-tool correction live on
  `chore/5.11-submission-handoff` to
  avoid another main-triggered Cloud upload.

`AppStore/submit.sh 5.11 51 --submit` succeeded and independently verified
WAITING_FOR_REVIEW and AFTER_APPROVAL at 19:10 CET. The follow-up read-only
`AppStore/submit.sh 5.11 51` confirmed the same exact submitted build without
changes. API verification at 18:10:36 UTC checked the selected build UUID and
number, release setting, version state and `usesNonExemptEncryption: false`.
Post-submission verification retained all 17 media placements and confirmed the
review attachment is COMPLETE. Submission log: `/tmp/n4x4-5.11-submit.log`;
read-only check: `/tmp/n4x4-5.11-final-check.log`. The known missing copyright
year precheck warning was non-blocking; the existing listing was preserved.

Review submission: `57c89ef5-5ec5-4ef0-a859-ba13ad5c50aa`, submitted at
`2026-10-27T18:10:05.792Z`, WAITING_FOR_REVIEW.

Final verification caught a release-tool defect: fastlane deliver 2.240.1
deletes existing review attachments when no replacement path is supplied.
It removed the initial `a99f85dd-6967-4979-94c7-ee79a74b8f9c` attachment during
metadata upload. The identical original video was restored to the submitted
version, then verified linked and COMPLETE under the final ID above. No review
was canceled or resubmitted. Version/build/release status remained unchanged.

`N4x4Release::PreserveReviewAttachments`, installed on deliver's metadata
uploader in `fastlane/Fastfile`, now skips attachment mutation when no explicit
replacement is supplied; explicit replacement retains deliver's normal behavior.
**6 release-tool tests / 21 assertions passed**, plus a check using the actual
installed deliver class. A subsequent read-only lane check also passed at
19:14 CET (`/tmp/n4x4-5.11-preservation-check.log`). Keep this tooling correction
off main until the next app version bump, because main still uploads on push.

Apple approval remains pending. The update releases automatically after
approval; no further publication action is required.
