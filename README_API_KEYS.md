# API Keys Configuration

This document explains how to configure API keys for The Paragliding App.

## How keys reach the app

Keys are **compile-time constants**, injected with `--dart-define`:

- **Local development**: `--dart-define-from-file=env.json` (gitignored)
- **CI / release**: `--dart-define=KEY=${{ secrets.KEY }}` from repository secrets

`lib/services/api_keys.dart` reads them via `String.fromEnvironment`. There is no runtime
file loading and no `.env`.

### Why not `.env`

`.env` was previously listed under `assets:` in `pubspec.yaml`. That copied the file verbatim
into every build, including release bundles. An `.aab` is a zip archive, so the keys could be
read straight out of a published app with `unzip` — no reverse engineering. Locally built
releases were published this way, so those keys are considered burned.

The asset declaration also meant a missing `.env` broke *every* command with
`Failed to build asset bundle`, which is why CI had to fabricate a placeholder before building.

### What dart-define does and does not give you

It removes the plaintext asset, which is a real improvement. It is **not** secrecy: dart-define
values are compiled into `libapp.so` and can be recovered with `strings` on the extracted
bundle.

Anything shipped inside a client app is public. The control that actually matters is
**restriction at the provider**:

- Scope Cesium Ion tokens to specific assets and the minimum permissions
- Pin Google Cloud keys to package `com.theparaglidingapp` plus the release signing fingerprint
- Prefer keys with per-key quotas, and watch provider dashboards for unexpected usage

If a key ever needs to be genuinely secret, it has to move behind a server-side proxy — the app
would call the proxy, and only the proxy would hold the key.

## Required API Keys

### 1. FFVL API Key (Required)

- **Purpose**: French paragliding weather beacons (`data.ffvl.fr` API)
- **Get it from**: <https://data.ffvl.fr/> (request via the FFVL data administration)
- **Note**: Free for non-commercial use; the FFVL emails the key

### 2. OpenAIP API Key (Optional)

- **Purpose**: Aviation data overlays (airspaces, airports, navaids, reporting points)
- **Get it from**: <https://www.openaip.net/>
- **Note**: Users can also configure their own in app settings

### 3. Cesium Ion Access Token (Optional)

- **Purpose**: 3D map visualization
- **Get it from**: <https://ion.cesium.com/tokens>

### Not Google Maps

The app uses `flutter_map` with OpenStreetMap. `google_maps_flutter` is not a dependency, and
there is no Google Maps key anywhere in the project — the Dart accessor, the
`com.google.android.geo.API_KEY` manifest entry and the iOS `GMSApiKey` entry were all dead
placeholders and have been removed. Adopting Google Maps tiles would mean adding the SDK and
wiring a key into the native config, not just setting an env var.

## Local Development Setup

```bash
cd the_paragliding_app
cp env.example.json env.json
$EDITOR env.json        # paste your keys
flutter pub get
```

`env.json` is gitignored. `bin/dev_run.sh` and `bin/flutter_controller_enhanced` pass it
automatically, and warn if it is missing. To run Flutter directly:

```bash
flutter run --dart-define-from-file=env.json
flutter build appbundle --release --dart-define-from-file=env.json
```

## Release builds

CI (`.github/workflows/build.yml`) injects each key from repository secrets. Add them under
**Settings → Secrets and variables → Actions**:

`FFVL_API_KEY`, `OPENAIP_API_KEY`, `CESIUM_ION_TOKEN`

For a local release build, pass `--dart-define-from-file=env.json` explicitly. A release built
without it will start and run, but FFVL weather, OpenAIP overlays and Cesium 3D will all be
unconfigured — check the startup log rather than assuming.

## Verifying a build

The app logs key status at startup:

```
[API_KEYS_STATUS] {ffvl_configured: true, openaip_configured: true,
                   cesium_configured: true, source: dart-define}
```

`source: none` means no keys were injected.

To confirm a bundle carries no plaintext keys:

```bash
unzip -l build/app/outputs/bundle/release/app-release.aab | grep -i env   # expect no matches
```

## Key Recovery

All keys are believed to be registered under **`kevin.mcisaac@gmail.com`** — verify before
re-requesting, and search Gmail for the confirmation message first (cheapest recovery path).

| Key | Provider portal | How to retrieve / reissue | Format hint |
|---|---|---|---|
| `FFVL_API_KEY` | <https://data.ffvl.fr/> | Email FFVL data administration. They reply with "voici votre clé API FFVL : ..." | 32-char lowercase hex |
| `OPENAIP_API_KEY` | <https://www.openaip.net/> | Log in → user profile → API keys → regenerate or copy existing | 32-char lowercase hex |
| `CESIUM_ION_TOKEN` | <https://ion.cesium.com/tokens> | Log in → Access Tokens → create a new token or copy the default | JWT, starts with `eyJ...` |

### Where keys live

| Location | Purpose | Tracked in git? |
|---|---|---|
| `the_paragliding_app/env.json` | Local development (`--dart-define-from-file`) | No — gitignored |
| GitHub repo → Settings → Secrets and variables → Actions | CI / release builds | N/A — server-side, write-only |
| `lib/services/api_keys.dart` | Code that reads the dart-define values | Yes (code only, no values) |

### Rotation

1. Reissue at the provider portal (table above).
2. Update `env.json` locally.
3. Update the matching GitHub Actions secret — old values cannot be read back, so
   `gh secret set NAME` to overwrite.
4. Restrict the new key at the provider where possible.

Treat `env.json` as a credential — never commit it, never paste it into chat or screenshots.
