# N4x4 5.16 — Fall Colors submitted for review

## Confirmed submission — 10 November 2026, 22:24 CET

The user requested a retry. The review attachment was COMPLETE with matching checksum, and the prepared review draft still had zero items. `AppStore/submit.sh 5.16 56 --submit` succeeded at 22:24:40 CET: **WAITING_FOR_REVIEW / AFTER_APPROVAL**. An independent read-only check confirmed that exact build and release setting at 22:24:53 CET. Review notes, listing and inherited media are unchanged; the review attachment remains COMPLETE with matching checksum. **5.16 is submitted, not yet live; 5.15 remains live pending approval.**

Evidence: `/tmp/n4x4-fall-release-review/submission-retry.log` and `confirmed-check.log`. Release source/tag and Cloud verification below remain unchanged. No new build or main push was needed.

## Historical preparation and blocker (resolved)

The state below records the earlier failed attempt, before the successful retry above.

## Exact source and release state

- Worktree: `/Users/marwin/.t3/worktrees/N4x4/feature-fall-colors-a45c9da1e2131d65`; branch `feature/fall-colors`.
- Release source on remote main: `a3cc6f6449cb40636014b48c40764ed337e53874`, tag `v5.16`.
- GitHub release: https://github.com/scripsweave/N4x4/releases/tag/v5.16
- Xcode Cloud **56**, run `a28ceb4b-7e51-462d-bf38-ae60d4ac9ffb`: all four actions SUCCEEDED for that exact commit. Downloaded Cloud result bundle: **325 passed, zero failed/skipped**, iPhone Duo / iOS 27.1. Cloud took an extra ten minutes timing out on simulator diagnostics collection after successful tests; the action ultimately passed.
- Build **5.16 (56)** is VALID and attached to version `d07bf6c4-5657-423b-beaf-00c05b099e1a`.
- Version remains **PREPARE_FOR_SUBMISSION**, release **AFTER_APPROVAL**. It is **not submitted or live**. 5.15 remains live.
- Empty review draft `85521c74-aebe-48c8-9bc5-b9a8ec9067ad` has **zero items**. No review was canceled or replaced.

## Genuine blocker and continuation

`AppStore/submit.sh 5.16 56 --submit` failed at 19:01 CET on 10 November with Apple's associated validation error:

> Attachment uploads still in progress. — The review attachment 24d2e0bb-faf6-48c0-b095-044200681b38 is still in progress.

The original approved physical-device evidence was re-uploaded from `~/.local/share/n4x4-review-evidence/N4x4-physical-device-review-5.12.mp4` (187094548 bytes). Fastlane completed all upload operations and finalization; a repeat finalization request was accepted. Apple still reports `UPLOAD_COMPLETE`, no errors, checksum not yet populated, after more than 40 minutes. Do not delete the attachment or cancel/recreate the review to work around processing. The user instructed stopping on genuine blockers, so work stopped at this external processing gate.

When the attachment becomes COMPLETE, verify its checksum against the private original and confirm that the draft remains empty. Then run:

```sh
AppStore/submit.sh 5.16 56
AppStore/submit.sh 5.16 56 --submit
```

The release is already authorized; no new source push/version bump/build is needed. Confirm WAITING_FOR_REVIEW and AFTER_APPROVAL after submission. If the draft has acquired items, inspect/finish that exact draft rather than blindly retrying or canceling it. The existing listing and inherited media were compared with 5.15 and retained. Review notes match `AppStore/review-notes-5.16.txt`. Fastlane's missing copyright-year warning was nonblocking; metadata was not changed to silence it.

## Feature and validation

Settings → Display → Appearance offers Default and Fall Colors. The explicit persisted choice changes decorative accents/surfaces on phone, Watch and Live Activity. Default and unknown stored/payload values preserve the original appearance. No automatic seasonal switching, health-zone recoloring or workout lifecycle change.

See [local TDD/visual report](FALL-COLORS-LOCAL-VERIFICATION.md) for exact changed files, RED/GREEN evidence, compact/Watch screenshots and limitations. Fresh independent release verification: 300 unit tests + appearance UI test passed (301 total), generic-device Release passed with all three bundles at 5.16, release tooling six tests/21 assertions passed. Reused simulator hosts stalled in HealthKit before tests; a fresh simulator passed without source/test relaxation.

Release evidence: `/tmp/n4x4-fall-release-review/`:

- `commands.txt`, `tests-fresh.xcresult`, `tests-summary.json`, `release.xcresult` and corresponding logs.
- `cloud-results/N4x4 Build 56 XCResult for N4x4 test-without-building on iPhone Duo (iOS 27.1).xcresult`, `cloud-summary.json`, `cloud-actions.json`, `cloud-56.json`.
- `screenshots/appearance-default-option.png`, `appearance-fall-option.png`, `appearance-default-home.png`, `appearance-fall-home.png`, `appearance-default-workout.png`, `appearance-fall-workout.png`, `appearance-fall-workout-landscape.png`, `appearance-restored-default-home.png`.
- `submission.log`, `final-state.json`, `attachment.json`, and read-only/finalization helper scripts. API credentials remain outside the repository and were never printed.

No physical-device validation was performed. The review video documents previously approved Bluetooth/background-audio behavior, not this appearance feature. Do not push this documentation-only follow-up to main on an already-uploaded version; keep it on the feature branch until the next authorized version bump.
