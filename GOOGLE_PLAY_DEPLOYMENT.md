# Google Play Deployment

Releases are built and published by `.github/workflows/build.yml`. Pushing a `v*` tag builds a
signed APK and App Bundle, verifies them, and publishes the bundle to the Play **internal**
track.

## Releasing

```bash
# 1. bump the build number (versionCode) - Play rejects a reused one
$EDITOR the_paragliding_app/pubspec.yaml     # version: 1.0.4+13

# 2. write the release notes users will see
$EDITOR distribution/whatsnew/whatsnew-en-GB

# 3. get both onto main the usual way (PR, review, merge)

# 4. tag the merged commit and push the tag
git switch main && git pull
git tag -a v1.0.4+13 -m "Release 1.0.4+13" && git push origin v1.0.4+13
```

Tag a commit that is already on `main` — CI refuses to release from anything else, so tagging a
branch and pushing both at once is no longer a shortcut that works.

### Release notes

`distribution/whatsnew/` holds one file per Play listing locale, named
`whatsnew-<locale>`, and CI passes the directory to the upload step. Max 500 characters each.

**The locale must exist in your Play listing or the upload is rejected.** This app's default
listing language is **English (United Kingdom) — `en-GB`**, hence `whatsnew-en-GB`. Add more files
to cover more locales; check Play Console → Store presence → Main store listing if in doubt.

Notes are worth writing whenever a release changes something users can see. 1.0.4 lowered every
user's total hours by about 11% by measuring takeoff-to-landing instead of the whole recording;
shipped without explanation, that reads as data loss rather than a correction.

## What happens when you push the tag

**There is no approval step.** The `play-internal` environment scopes the signing and Play
credentials to this one job so no other workflow can read them, but it carries no protection
rules — a pushed tag publishes without waiting for anyone. This file used to claim a required
reviewer; there has never been one. Add required reviewers under Settings → Environments →
`play-internal` if a human checkpoint is wanted. Until then the tag push *is* the decision.

Four cheap checks run first, all within seconds, so a bad tag fails long before a ~15 minute
build:

| check | fails when |
|---|---|
| tag matches `pubspec.yaml` | tagged without bumping |
| `versionCode` exceeds every existing `v*` tag | the `+N` suffix was reused — Play otherwise only says so *after* the upload |
| tagged commit is an ancestor of `main` | the tag points at an unmerged branch or an arbitrary commit |
| `whatsnew-en-GB` exists and is ≤500 characters | notes were forgotten, or overrun Play's limit |

`flutter analyze` and the full test suite run alongside them, and the build does not start
unless they pass. That gate lives here rather than relying on `ci.yml` because nothing requires
`ci.yml` to be green before merging or tagging — a tag on a red commit used to build and publish
exactly like a green one.

Then CI:

1. Restores the upload keystore and writes `android/key.properties`
2. Builds APK + AAB with the API keys injected via `--dart-define`
3. **Verifies both artifacts** (see below) — hard failure, not a warning
4. Records a build provenance attestation for each
5. Publishes the AAB to the internal track with `mapping.txt`
6. Attaches the APK to a GitHub Release, carrying the same notes Play testers see

Internal testing has no review delay; testers see it within minutes.

`workflow_dispatch` runs the same tests, build, verification and attestation but **does not
publish** — use it to test pipeline changes, against a branch:

```bash
gh workflow run build.yml --ref my-branch
```

**What the dry run does not cover.** Anything gated on a tag ref: the four checks in the table
above, the Play upload, and the GitHub release. Those first run for real on the next tag. If you
need to prove one of the tag checks without publishing, tag an *unmerged* commit — the
ancestor-of-`main` check fails, so nothing is built and nothing is uploaded. Delete the throwaway
tag afterwards, and confirm with `git ls-remote --tags origin`.

## What CI verifies

Two failure modes that produce a perfectly normal-looking build, both hard errors:

| check | why |
|---|---|
| signing cert == `vars.UPLOAD_CERT_SHA256` | Without `key.properties`, `build.gradle.kts` falls back to the **debug** key and only `println`s a warning. Play rejects the upload, and before this check GitHub Releases were being published debug-signed. |
| no `flutter_assets/.env` in the artifact | `.env` was once declared as an asset, shipping API keys in plaintext to every user (#284). This stops that regressing. |

Both run against **the APK as well as the AAB**. They used to cover only the AAB, which is the
artifact Play re-signs and independently validates anyway; the APK is the one attached to the
GitHub release and sideloaded directly, so it was the copy reaching users unexamined.

The two need different tools. An AAB is jar-signed, so `keytool -printcert -jarfile` reads it.
An APK may carry only an APK Signature Scheme v2/v3 block, which `keytool` cannot see at all —
it reports "not a signed jar file" on a perfectly good APK — so the APK is read with
`apksigner verify --print-certs` and the two fingerprints are normalised before comparing.

Beyond verification, each artifact gets a **build provenance attestation**, which lets anyone
check that a downloaded APK came from this workflow at this commit:

```bash
gh attestation verify app-release.apk --repo Kevin-McIsaac/the_paragliding_app
```

The expected fingerprint is a repository **variable**, not a secret — it is a public certificate
fingerprint:

```
UPLOAD_CERT_SHA256 = 1F:05:AD:55:3A:CB:78:8C:38:CB:13:7D:61:06:B6:D6:EC:3C:04:0D:90:89:AA:A8:00:14:70:6E:63:7A:7E:F2
```

## Configuration

### Environment `play-internal` (already created)

No protection rules — see above. Its purpose is scoping: signing and Play credentials live here
rather than on the whole repository, so no other workflow can read them.

**Environment secrets** (set from the local keystore):

| secret | source |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 upload-keystore-new.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | `storePassword` in `android/key.properties` |
| `ANDROID_KEY_ALIAS` | `upload` |
| `ANDROID_KEY_PASSWORD` | `keyPassword` in `android/key.properties` |
| `PLAY_STORE_SERVICE_ACCOUNT_JSON` | **still to be set** — see below |

**Repository secrets** (shared with `ci.yml`): `FFVL_API_KEY`, `OPENAIP_API_KEY`,
`CESIUM_ION_TOKEN`.

### Remaining setup: the Play service account

This cannot be scripted — it needs the Google Cloud and Play Console UIs.

1. **Play Console → Setup → API access → Create new service account**, following the link into
   Google Cloud Console
2. In Google Cloud: create the service account, then **Create Key → JSON** and download it
3. Back in Play Console → API access → **Grant access** to that service account, with at least
   **Release management** and **View app information**, scoped to this app
4. Add the JSON as an environment secret:
   ```bash
   gh secret set PLAY_STORE_SERVICE_ACCOUNT_JSON --env play-internal < service-account.json
   rm service-account.json
   ```

Permission changes in Play Console can take a few minutes to take effect.

## Why the keystore is safe to put in CI

This app is enrolled in **Play App Signing**, so `upload-keystore-new.jks` is an *upload* key —
Google holds the actual app signing key. A compromised upload key can be reset through Play
Console. If the project were self-signing, putting the key in CI would risk permanently losing
the ability to update the listing, and this pipeline would be a bad idea.

Keep a backup of the keystore **and** `key.properties` regardless; the passwords are useless
without the keystore and vice versa.

## Pinned actions

Every `uses:` in `build.yml` and `ci.yml` names a commit SHA with its release in a trailing
comment, not a tag. `@v1` is a movable ref: whoever controls the action repository can repoint it
at new code, and it would run here on the next release with nothing changing in this repo. That
matters more than usual because `release-android` holds the upload keystore and its passwords,
and hands the Play service account JSON to a third-party action (`r0adkll/upload-google-play`).

The cost is that pins go stale silently — a pinned action is never told about its own security
fixes. To update one:

```bash
gh api repos/actions/checkout/commits/v7 -q .sha   # resolve the tag to a commit
```

then edit the SHA **and** the version comment together, and prove it with
`gh workflow run build.yml --ref <branch>`.

## Version management

`pubspec.yaml` is the single source of truth for all three numbers Play shows, which are easy to
confuse:

| | example | what it is |
|---|---|---|
| `versionCode` | `12` (the `+N` suffix) | Play's real identity for a build. Must strictly increase, can never be reused. |
| `versionName` | `1.0.3` | The only version users ever see. Changes only when you change it. |
| Release name | `12 (1.0.3)` | A Play Console label. Cosmetic, ordering-irrelevant, set by CI from the two above. |

CI derives the release name so API uploads match the `<versionCode> (<versionName>)` format Play
Console generates for manual uploads — without it, an API upload is labelled with just the
versionName and the track history changes format partway down the list.

Bump `versionName` when a release contains user-visible change. Builds 5 through 11 all shipped
as `1.0.2`, which left users unable to tell a months-old build from a current one.

Do **not** switch to `github.run_number` — earlier releases were built locally from pubspec, so a
run-number scheme would desynchronise from what is already published.

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `Tag vX does not match pubspec version` | Tagged without bumping | Bump `pubspec.yaml`, retag |
| `versionCode N was already released as vX` | The `+N` suffix was reused | Bump it; this is the local form of Play's `Version code N has already been used` |
| `... is not an ancestor of main` | Tag points at an unmerged or arbitrary commit | Merge first, then tag the merge commit |
| `whatsnew-en-GB is missing or empty` | Release notes not written | Write them; step 2 of Releasing |
| `AAB is not signed with the upload key` | Keystore secret missing or wrong | Check the `play-internal` environment secrets |
| `APK is not signed with the upload key` | Same cause; the APK is checked separately with `apksigner` | As above |
| `.env is bundled in ...` | Someone re-added `.env` to `assets:` | Remove it; keys come from `--dart-define` (see README_API_KEYS.md) |
| `Version code N has already been used` | Reached Play despite the check above — e.g. a build uploaded manually | Bump the `+N` suffix |
| `The caller does not have permission` | Service account lacks Play access | Re-check the grant in Play Console → API access |
| `Invalid JWT` | Malformed service account JSON secret | Re-set it from the original file with `gh secret set ... <` |

## Promoting to production

Deliberately manual. Test on the internal track, then promote the release in Play Console →
Production, ideally as a staged rollout. Nothing in CI touches the production track.
