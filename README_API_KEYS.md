# API Keys Configuration

This document explains how to configure API keys for The Paragliding App.

## Overview

The app uses a hybrid approach for API key management:

- **Development**: Uses `.env` file with flutter_dotenv
- **Production**: Uses GitHub Secrets with `--dart-define`

## Required API Keys

### 1. FFVL API Key (Required)

- **Purpose**: Access French paragliding weather beacons
- **Get it from**: <https://balisemeteo.com/api/>
- **Note**: Appears to be public

### 2. Google Maps API Key (Optional)

- **Purpose**: Google Maps integration (if using Google Maps instead of OpenStreetMap)
- **Get it from**: <https://console.cloud.google.com/apis/credentials>
- **Note**: App defaults to OpenStreetMap, so this is optional

### 3. OpenAIP API Key (Optional)

- **Purpose**: Aviation data overlays (airspaces, airports, etc.)
- **Get it from**: <https://www.openaip.net/>
- **Note**: User can configure this in app settings

### 4. Cesium Ion Access Token (Optional)

- **Purpose**: 3D map visualization with Cesium
- **Get it from**: <https://ion.cesium.com/tokens>
- **Note**: Required only for 3D map features

## Local Development Setup

### Step 1: Copy the example file

```bash
cd the_paragliding_app
cp .env.example .env
```

### Step 2: Edit `.env` and add your keys

```env
FFVL_API_KEY=your_FFVL_API_key_here
GOOGLE_MAPS_API_KEY=your_google_maps_key_here
OPENAIP_API_KEY=your_openaip_key_here
CESIUM_ION_TOKEN=your_cesium_ion_token_here
```

### Step 3: Run the app

```bash
flutter pub get
flutter run
```

The app will automatically load keys from `.env` file.

## Production Setup (GitHub Actions)

### Step 1: Add secrets to GitHub repository

1. Go to your repository on GitHub
2. Navigate to Settings → Secrets and variables → Actions
3. Add the following secrets:
   - `FFVL_API_KEY`
   - `GOOGLE_MAPS_API_KEY`
   - `OPENAIP_API_KEY`
   - `CESIUM_ION_TOKEN`

### Step 2: Build with GitHub Actions

The workflow in `.github/workflows/build.yml` will automatically inject the API keys during build:

```yaml
flutter build apk --release \
  --dart-define=FFVL_API_KEY=${{ secrets.FFVL_API_KEY }} \
  --dart-define=GOOGLE_MAPS_API_KEY=${{ secrets.GOOGLE_MAPS_API_KEY }} \
  --dart-define=OPENAIP_API_KEY=${{ secrets.OPENAIP_API_KEY }}
```

## Manual Production Build

To build locally with production keys:

```bash
flutter build apk --release \
  --dart-define=FFVL_API_KEY=your_ffvl_key \
  --dart-define=OPENAIP_API_KEY=your_openaip_key \
  --dart-define=CESIUM_ION_TOKEN=your_cesium_token
```

## How It Works

The `ApiKeys` service (`lib/services/api_keys.dart`) provides a fallback pattern:

1. **First**: Checks for `--dart-define` values (production)
2. **Second**: Falls back to `.env` file (development)
3. **Third**: Returns empty string or placeholder

```dart
static String get ffvlApiKey {
  // Try dart-define first (production)
  const fromEnv = String.fromEnvironment('FFVL_API_KEY');
  if (fromEnv.isNotEmpty) return fromEnv;

  // Fall back to dotenv (development)
  final fromDotenv = dotenv.env['FFVL_API_KEY'] ?? '';
  if (fromDotenv.isNotEmpty) return fromDotenv;

  return '';
}
```

## Security Notes

1. **Never commit `.env` file** - It's in `.gitignore`
2. **Use `.env.example`** as a template (safe to commit)
3. **Keep production keys in GitHub Secrets**
4. **Rotate keys regularly** if they get exposed
5. **Use different keys** for development and production

## Troubleshooting

### App says "No FFVL API key found"

- Check that `.env` file exists in `the_paragliding_app/` directory
- Verify the key is set: `FFVL_API_KEY=12fbb9720455a2abb825c29233ac8bd0`
- Run `flutter clean` and `flutter pub get`

### Build fails in GitHub Actions

- Verify secrets are set in repository settings
- Check workflow has access to secrets
- Review build logs for specific errors

### Keys not loading in release build

- Ensure you're using `--dart-define` when building
- Keys from `.env` only work in debug mode
- Production builds require `--dart-define` or CI/CD

## API Key Status

The app logs API key configuration status on startup:

```
[API_KEYS_STATUS] {
  ffvl_configured: true,
  google_maps_configured: false,
  openaip_configured: false,
  cesium_configured: false,
  source: dotenv
}
```

This helps debug which keys are loaded and from what source.
