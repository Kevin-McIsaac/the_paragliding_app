# Google Play Deployment

Releases are built and published by `.github/workflows/build.yml`. Pushing a `v*` tag builds a
signed APK and App Bundle, verifies them, and publishes the bundle to the Play **internal**
track.

## Releasing

```bash
# 1. bump the build number (versionCode) - Play rejects a reused one
$EDITOR the_paragliding_app/pubspec.yaml     # version: 1.0.4+13
git commit -am "chore: Bump build number to 1.0.4+13"

# 2. write the release notes users will see
$EDITOR distribution/whatsnew/whatsnew-en-GB

# 3. tag and push
git tag v1.0.4+13 && git push origin main --tags
```

### Release notes

`distribution/whatsnew/` holds one file per Play listing locale, named
`whatsnew-<locale>`, and CI passes the directory to the upload step. Max 500 characters each.

**The locale must exist in your Play listing or the upload is rejected.** This app's default
listing language is **English (United Kingdom) — `en-GB`**, hence `whatsnew-en-GB`. Add more files
to cover more locales; check Play Console → Store presence → Main store listing if in doubt.

Notes are worth writing whenever a release changes something users can see. 1.0.4 lowered every
user's total hours by about 11% by measuring takeoff-to-landing instead of the whole recording;
shipped without explanation, that reads as data loss rather than a correction.

The tag must agree with `pubspec.yaml` — the `check-version` job fails fast otherwise, rather
than letting Play reject the upload after a full build.

Then **approve the deployment**: the `release-android` job targets the `play-internal`
environment, which has a required reviewer, so it waits in the Actions tab until approved. That
is the last point at which a mistaken tag can be stopped.

After approval, CI:

1. Restores the upload keystore and writes `android/key.properties`
2. Builds APK + AAB with the API keys injected via `--dart-define`
3. **Verifies** the bundle (see below) — hard failure, not a warning
4. Publishes the AAB to the internal track with `mapping.txt`
5. Attaches the APK to a GitHub Release

Internal testing has no review delay; testers see it within minutes.

`workflow_dispatch` runs the same build and verification but **does not publish** — use it to
test pipeline changes.

## What CI verifies

Two failure modes that produce a perfectly normal-looking build, both now hard errors:

| check | why |
|---|---|
| AAB signing cert == `vars.UPLOAD_CERT_SHA256` | Without `key.properties`, `build.gradle.kts` falls back to the **debug** key and only `println`s a warning. Play rejects the upload, and before this check GitHub Releases were being published debug-signed. |
| no `flutter_assets/.env` in the bundle | `.env` was once declared as an asset, shipping API keys in plaintext to every user (#284). This stops that regressing. |

The expected fingerprint is a repository **variable**, not a secret — it is a public certificate
fingerprint:

```
UPLOAD_CERT_SHA256 = 1F:05:AD:55:3A:CB:78:8C:38:CB:13:7D:61:06:B6:D6:EC:3C:04:0D:90:89:AA:A8:00:14:70:6E:63:7A:7E:F2
```

## Configuration

### Environment `play-internal` (already created)

Required reviewer: repository owner. Signing and Play credentials are scoped to this
environment rather than the whole repository, so no other workflow can read them.

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
| `AAB is not signed with the upload key` | Keystore secret missing or wrong | Check the `play-internal` environment secrets |
| `.env is bundled as an asset` | Someone re-added `.env` to `assets:` | Remove it; keys come from `--dart-define` (see README_API_KEYS.md) |
| `Version code N has already been used` | `versionCode` not bumped | Bump the `+N` suffix |
| `The caller does not have permission` | Service account lacks Play access | Re-check the grant in Play Console → API access |
| `Invalid JWT` | Malformed service account JSON secret | Re-set it from the original file with `gh secret set ... <` |

## Promoting to production

Deliberately manual. Test on the internal track, then promote the release in Play Console →
Production, ideally as a staged rollout. Nothing in CI touches the production track.
