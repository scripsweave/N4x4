# Health & Devices and recoverable Health exports

Release **5.6** authorized on 2026-09-29. All six shipping configurations
are bumped to 5.6. Implementation was prepared on
`feature/health-devices-reliable-saves`; release delivery uses main and Xcode
Cloud. Submission status will be recorded after Apple's API confirms it.

## User-facing behavior

Settings now has one Health & Devices destination for the two existing Health
preferences, write permission, confirmed/pending saves, Watch and Bluetooth
connections, AirPods heart rate, source order, Cardio Fitness, optional birthday
availability, and privacy-conscious diagnostics. Old settings search results
route to the relevant section. Pairing and Watch help remain focused sheets.
Opening settings does not request authorization or start a Bluetooth scan.

Health write authorization is independent of the user's enabled preference.
Read permissions cannot be inferred from missing data. Permission-sheet success
is not treated as a grant. Watch streaming status uses the Watch's own fresh
sample, not the selected value from a Bluetooth monitor.

Completion review and History show each session's Health save status. Unknown
older sessions can be checked and explicitly exported, including approximate
start-time disclosure where only a duration remains. Only N4x4-authored Health
records are considered matches. Ambiguous matches are offered for selection;
empty or failed queries still require confirmation before making a new copy.
Deleting local History does not delete previously exported Health workouts.

## Persistence and concurrency

`WorkoutLogEntry.healthExport` is optional. It contains immutable numeric start
and end timestamps, pending/saved/notRequested state, attempts, error, and the
confirmed Health UUID/date. Numeric timestamps preserve precision despite the
History JSON encoder using ISO dates. Missing metadata means unknown, not failed.
Damaged optional-field recovery preserves independently readable export state.

TimerViewModel owns the queue, derived from persisted History. Local completion,
recovery and Watch imports store intent before attempting Health. Watch ack still
requires the local log and series; it does not wait for Health. An outstanding
series save prevents exporting that local completion until recovery succeeds.
Review edits preserve the export record. New sessions with saving disabled are
not automatically backfilled when enabled later.

Exports drain serially on completion, launch, foreground, authorization callback,
logging re-enable, or explicit retry. Each ID is attempted once per drain; new
entries arriving while awaiting a save join the same drain. Both preferences and
fresh write authorization gate saves. UIKit's bounded background task covers
Health work after workout audio stops, without relying on background execution
for durability. Late callbacks cannot resurrect deleted entries.

The injected HealthWorkoutExportClient is the system boundary. The system client
uses HKMetadataKeySyncIdentifier = `N4x4.workout.<UUID>` and sync version 1 for
immutable exports. Nil/error duplicate results require finding that identity
before acknowledging success; otherwise the request stays pending. A failed local
acknowledgement leaves the original pending state for an idempotent retry.

Legacy matching uses stable metadata first, then a unique original start/end
match within one second. Approximate timing never auto-confirms a date match.
Source filtering happens on returned samples rather than HKSource.default(): the
latter raises an Objective-C exception in unsigned/unentitled simulator builds.
Query errors are recoverable and shown in the legacy confirmation flow.

## Validation and limits

- Full unit suite: **203 passed**, including 17 new Health export tests.
- iPhone SE 3 (iOS 26.5): **5 UI tests passed**, covering pending/confirmed
  status, no prompts on entry, large text/search, legacy recovery confirmation,
  and History deletion. `/tmp/N4x4-health-final-se.xcresult`.
- iPhone 17 Pro Max (iOS 26.5): **4 UI tests + 17 export tests passed** after
  the source-query correction and native source-order edit-mode fix.
  `/tmp/N4x4-health-final-pro.xcresult`.
- The initial Pro Max recovery test exposed an unsigned-build exception from
  HKSource.default(). It was fixed; both final test diagnostics contain zero
  `.ips` crash reports. Expected unsigned Health entitlement query errors are
  handled as recoverable failures, not successful writes.
- Unsigned generic-device Release build passed, including embedded Watch and
  Live Activity. `/tmp/N4x4-health-release-verified.log`. Project plist validation and
  `git diff --check` passed.
- Final privacy regression passed after removing the numeric Cardio Fitness
  reading from diagnostics. `/tmp/N4x4-health-privacy.xcresult`.
- Native screenshots were reviewed for small/large screens and largest Dynamic
  Type. Native reorder handles are visible after moving edit mode to the Form.
  Previews: `~/Desktop/N4x4 Health & Devices/preview.html` (test fixture data).
- Design review: **8/10**. Native navigation, controls, semantic type/colors,
  and scrollable large-text layouts are verified. Reaching 10/10 still needs
  physical VoiceOver/reordering and on-device contrast/touch checks. The app's
  existing forced-dark presentation remains; no light-mode policy was added.

Physical-device checks remain required: offline and locked-phone Health writes,
repeated sync-identifier exports producing one Health workout, standalone Watch
transfer, revoked/re-granted permissions, and VoiceOver operation. No physical
devices were connected during implementation. Simulator tests inject the Health
boundary and do not prove real HealthKit writes. Louise's exact original cause
has not been established.

The screen follows the app's existing dark appearance and uses semantic native
Form controls, colors and text styles. A change to the app-wide appearance policy
is outside scope. The current HIIT export contents (including existing timing and
classification behavior) are preserved; no calorie estimates or HR samples were
added to Health exports.
