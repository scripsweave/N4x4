# App Store submissions

**Latest submission (2026-10-29):** `AppStore/submit.sh 5.14 54 --submit`
verified **WAITING_FOR_REVIEW** and **AFTER_APPROVAL** at 15:26 CET;
independent verification and read-only check confirmed it at 15:27 CET.
Cloud **54** passed all four actions and **309/309 test records** for
`54682f4671acab643d40ea319fe16856052c2a07` / `v5.14`.
All 17 screenshot/header placements, existing listing and COMPLETE private
physical-device review video are retained. **5.11 remains live until approval.**
See the [5.14 handoff](../docs/SESSION-HANDOFF-2026-10-29-RELEASE-5.14.md).
Candidates 5.12/52 and 5.13/53 were never submitted; their failed UI checks were
corrected and passed in Cloud 54. Earlier preparation records below are historical.


**5.14 preparation (2026-10-29):** The 5.13 candidate passed 308/309 test records
but its first UI launch was interrupted by a leftover unit-test notification
popup. Test setup now clears that popup before launch; a fresh Duo reproduced
it and passed 285 unit + five UI checks. Seven focused UI checks also pass.
Idle-launch audio activation is deferred until playback. All three Release
bundles build as 5.14. See the [current handoff](../docs/SESSION-HANDOFF-2026-10-29-RELEASE-5.14.md).

**5.13 release preparation (2026-10-29):** Fresh candidate after 5.12 Cloud 52
failed its required UI action. Compact-Duo scrolling and isolated launch capture
setup are corrected; five focused Duo checks and generic-device Release builds
pass. Same authorized feature set. The editable App Store draft is renamed to
5.13 with existing media/review evidence retained. See the
[5.13 handoff](../docs/SESSION-HANDOFF-2026-10-29-RELEASE-5.13.md).

**5.12 preparation (2026-10-29):** Source/tag `0655ac6` / `v5.12` is on main;
Release builds and the full regression (285 unit + 26 UI tests) pass. App Store draft, release/review notes, all 17 inherited
media placements and COMPLETE private review video are verified. **Cloud is
blocked by the updated Developer Program License Agreement**, which Xcode says
the Account Holder must accept. No new binary or review submission yet. User
was asked to accept at developer.apple.com/account; release authorization is
already given. See the [5.12 handoff](../docs/SESSION-HANDOFF-2026-10-29-RELEASE-5.12.md)
for exact identifiers and continuation steps. 5.11 is live.

After the user's first “done”, Apple still reported the agreement as pending.
The exact [agreement page](https://developer.apple.com/account/agree/LC644S5URF/terms)
is open in Safari with Agree available; no agreement was accepted by the agent.
All original Cloud workflow conditions and actions have been restored and
verified after the earlier manual-tag trial.

N4x4 has a repeatable API-based submission command. It promotes a specific
build already uploaded by Xcode Cloud; Safari and Apple ID sessions are not
needed. This is an on-demand release tool, not a scheduled job.

**Latest submission (2026-10-27):** `AppStore/submit.sh 5.11 51 --submit`
verified **WAITING_FOR_REVIEW** and **AFTER_APPROVAL** at 19:10 CET. Cloud 51
passed all four required actions and **270/270 tests** for release source/tag
`ea361a306fda3080fa74acad4dba8170d16cf6aa` / `v5.11`. Existing listing,
screenshots and animated header were preserved, and the original private
physical-device review evidence is attached and processed. **5.10 remains
live pending approval of 5.11.** See the
[5.11 handoff](../docs/SESSION-HANDOFF-2026-10-27-WORKOUT-EXPORT.md).

**Review attachment preservation:** fastlane deliver 2.240.1 deletes existing
App Review attachments when `app_review_attachment_file` is omitted. The lane
now installs `N4x4Release::PreserveReviewAttachments` to leave existing evidence
untouched unless a replacement file is explicitly provided. Six release-tool
tests / 21 assertions and the actual installed deliver class verify this guard.
During 5.11 submission, final verification caught this behavior and the original
video was restored to the already-submitted version, verified linked and
COMPLETE, without canceling/resubmitting. The correction is on
`chore/5.11-submission-handoff`; include it with the next main version bump.

## Release workflow

1. Finish the change and appropriate simulator/device tests. Bump
   `MARKETING_VERSION` in all six **shipping** configurations (phone, Watch,
   Live Activity; Debug/Release). Leave test-target versions alone.
2. Write `AppStore/release-notes-VERSION.txt` with the English (U.S.) What's
   New text. Keep the existing listing and screenshots unless changing them
   deliberately as part of the release.
3. Commit/push the release, tag it and create the GitHub release. Main is
   watched by Xcode Cloud, so treat each main push as an upload. If Cloud
   doesn't start automatically, start the Default workflow on the intended
   commit in App Store Connect. Confirm that commit and note its build number.
4. From the repository root, run the submission command with those exact
   numbers. For example, after a future 5.5 / build 41 upload:

   ```sh
   AppStore/submit.sh 5.5 41            # read-only check
   AppStore/submit.sh 5.5 41 --submit   # submit and release after Apple approval
   ```

The submit command waits up to 20 minutes for that exact build to appear and
finish processing. It creates/updates the App Store version, supplies release
notes, attaches the build, submits for review, and verifies the resulting
status. Automatic release is enabled, phased release is disabled, and ratings
are preserved. Apple still decides when to approve the submission; a successful
submission is **not** evidence that the update is already live.

The command refuses mismatched project versions, failed/expired builds,
another active release, and drafts already containing review items. Repeating
it for the same submitted build is a no-op. It never cancels a review or
replaces a different submitted build. If a network interruption leaves a
partially prepared review draft, inspect/finish that draft in App Store
Connect before retrying; do not cancel it blindly.

**Cloud workflow API updates:** When changing start conditions, include the
complete saved set of automatic and manual conditions in the PATCH payload.
Apple replaces the condition set: sending only `manualTagStartCondition` cleared
the existing main/manual-branch conditions during 5.12 preparation. They were
restored from the pre-change snapshot and verified together with all actions.
A null-only PATCH did not restore the missing fields. Keep the original
snapshot and compare every condition after any workflow mutation.

The export-compliance answer follows N4x4's current implementation: it does
not implement non-exempt encryption. Revisit the lane's
`export_compliance_uses_encryption` setting if that changes. A build already
declaring non-exempt encryption is rejected by the guard.

## Local setup

Configured on this Mac on 2026-09-25:

- Homebrew fastlane **2.240.1** (release tooling only; no app dependency).
- App Store Connect team key named **N4x4 Release Automation**, App Manager
  role. Apple team keys apply across the account; this tool is hard-coded to
  N4x4's app ID `6686407796` and bundle ID `Jan-van-Rensburg.N4x4`.
- Credential: `~/.config/n4x4/app-store-api-key.json`, owner-only permissions
  (`600`, enclosing directory `700`). It contains the downloaded private key
  and must stay outside the repository. The downloaded copy was removed.
- Override the path with `N4X4_ASC_KEY_PATH` when using another machine.

On another Mac, install `brew install fastlane` and provision a credential
outside the checkout. The JSON uses fastlane's `key_id`, `issuer_id`, `key`
(PEM contents), and `in_house: false` fields. Never paste private-key contents
into a chat, log, or tracked file. Revoke/replace this key through Users and
Access → Integrations → App Store Connect API if this Mac loses access.

No GitHub secret, scheduled job, or automatic submission-on-push was added.
The agent runs this command as part of an authorized release. This keeps
routine commits from becoming review submissions. Don't push a tooling-only
change to main while it still has an already-uploaded marketing version;
include it with the next version bump instead.

## Verification

```sh
ruby fastlane/release_support_test.rb
AppStore/submit.sh 5.4 40
```

Four tests / 18 assertions cover wrong builds, partial version bumps, invalid
builds, review drafts, and duplicate submission handling. The live read-only
check verified 5.4 (40), `WAITING_FOR_REVIEW`, `AFTER_APPROVAL`. The repeat
submission path was also checked against that same build without making
changes. Creation and submission received their first successful live verification
on 2026-09-27: `AppStore/submit.sh 5.5 41 --submit` attached build 41, supplied
the release notes and verified WAITING_FOR_REVIEW with AFTER_APPROVAL.
The new screenshots were uploaded and verified separately before running the
submission command (the lane deliberately preserves them). Version 5.4 was
submitted through Safari before this automation was added.

Latest verified submission: 2026-10-02, `AppStore/submit.sh 5.9 45 --submit`.
All three Xcode Cloud actions passed for release commit `358a46f`. The lane
verified build 45 was VALID, uploaded the release notes, and confirmed
**WAITING_FOR_REVIEW** with **AFTER_APPROVAL** at 22:38 CEST. Existing
screenshots/listing were retained. Version 5.7 remains live pending approval.

The user authorized this new release while 5.8 (44) was waiting for review.
After 5.9 (45) passed Cloud and became VALID, the exact 5.8 review submission
was explicitly canceled and its editable version record changed to 5.9.
The standard submission tool then attached and submitted build 45. This was
a separately verified supersession; the tool itself still never cancels or
replaces a different submitted version. See
[`../docs/SESSION-HANDOFF-2026-10-02-WORKOUT-TIMING.md`](../docs/SESSION-HANDOFF-2026-10-02-WORKOUT-TIMING.md).

References: [fastlane deliver](https://docs.fastlane.tools/actions/deliver/),
[API-key authentication](https://docs.fastlane.tools/app-store-connect-api/),
[Apple's API access guide](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api/).

## 5.10 resubmission after a rejection

On 24 October 2026, version 5.10 (50) reused the existing rejected review submission. All four Cloud actions and 262 tests passed for release commit `fb9d1c8`; six Duo screenshots and a processed private physical-device video were verified first. The video joins the Bluetooth demonstration and Home Screen audio demonstration because App Review Information accepts one attachment.

The normal lane deliberately refuses unresolved review drafts. The existing rejected item was resolved through `PATCH /v1/reviewSubmissionItems/{id}` with `resolved: true`, then the same review was resubmitted through `PATCH /v1/reviewSubmissions/{id}` with `submitted: true`. Read item status via the review submission's `/items` relationship; the API does not support an individual item GET. No review was canceled or removed.

`AppStore/submit.sh 5.10 50 --submit` independently confirmed **WAITING_FOR_REVIEW** and **AFTER_APPROVAL** at 21:45 CEST. This is the latest verified submission; 5.7 remains public until approval. See the [5.10 handoff](../docs/SESSION-HANDOFF-2026-10-24-DUO.md) and [Apple's unresolved-submission workflow](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/manage-a-submission-with-unresolved-issues).
