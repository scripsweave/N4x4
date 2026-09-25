# App Store submissions

N4x4 has a repeatable API-based submission command. It promotes a specific
build already uploaded by Xcode Cloud; Safari and Apple ID sessions are not
needed. This is an on-demand release tool, not a scheduled job.

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
changes. Creation and submission of a new version will receive its first
live API verification on the next release; 5.4 was submitted through Safari
before this automation was added.

References: [fastlane deliver](https://docs.fastlane.tools/actions/deliver/),
[API-key authentication](https://docs.fastlane.tools/app-store-connect-api/),
[Apple's API access guide](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api/).
