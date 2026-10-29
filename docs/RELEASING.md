# Releasing the Mac app

A signed direct download is built by the `Mac release` workflow. Everything it needs is below. None of
it can be created from the repository; each item comes from your Apple Developer account.

## Secrets

Add these under the repository's Settings → Secrets and variables → Actions.

| Secret | What it is |
| --- | --- |
| `DEVELOPER_ID_CERT_P12` | A **Developer ID Application** certificate with its private key, exported from Keychain Access as a `.p12`, then base64-encoded: `base64 -i cert.p12 \| pbcopy`. |
| `DEVELOPER_ID_CERT_PASSWORD` | The password you gave that `.p12`. |
| `DEVELOPER_ID_PROFILE` | A **Developer ID** provisioning profile for `me.fybre.dosebook` on macOS, with iCloud (CloudKit, container `iCloud.me.fybre.dosebook`) and Push Notifications, base64-encoded the same way. The iCloud entitlement is restricted, so a Developer ID build cannot sign without it. |
| `APPLE_API_KEY_P8` | An App Store Connect API key (`AuthKey_XXXX.p8`, role Developer or higher), base64-encoded. Used only to have Apple notarise the app. |
| `APPLE_API_KEY_ID` | That key's ID. |
| `APPLE_API_ISSUER_ID` | The issuer ID shown on the API keys page. |

Never commit any of these. Pull requests from forks cannot read them, and the release workflow only runs on
tags and manual runs, so a pull request cannot reach them.

## Before the first release

1. In the CloudKit Console, deploy the schema from Development to **Production**. A Developer ID app uses
   the production environment, and sync will not work until this is done.
2. Create the profile above in the developer portal (Certificates, Identifiers & Profiles → Profiles →
   Developer ID).

## Making a release

Push a tag: `git tag v1.0.0 && git push origin v1.0.0`. The workflow archives, signs, notarises, staples,
builds `Dosebook-1.0.0.dmg` and attaches it to a GitHub release. Or use Actions → Mac release → Run workflow
and enter a version; that builds and uploads the DMG as a workflow artifact without publishing a release.

The build number is the workflow run number.

## Known gaps

The app needs Xcode 27 or later: Swift 6.2, in every Xcode 26.x tried (26.2 to 26.6), crashes while generating
code for it. The release workflow and the CI build job run on GitHub's `xcode-27` runner image for that reason,
and say so if a runner ever has an older Xcode. The cause inside the app has not been found.

The workflow has not been run end to end. The likeliest places for a first run to fail are the profile
name lookup, the export options, and the push environment: the checked-in entitlements ask for the
*development* push environment, so the workflow writes a copy that says *production* and signs with that.
