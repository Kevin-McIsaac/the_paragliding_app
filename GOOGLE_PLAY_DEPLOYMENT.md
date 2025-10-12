# Google Play Automated Deployment

This guide explains how to set up automated deployment to Google Play Store using GitHub Actions.

## Prerequisites

1. **Google Play Developer Account** ($25 one-time fee)
2. **Published app** (at least one manual upload)
3. **App signing by Google Play** (recommended)

## Setup Steps

### Step 1: Create Service Account

1. Go to [Google Play Console](https://play.google.com/console)
2. Navigate to **Setup → API access**
3. Click **Create new service account**
4. Follow the link to Google Cloud Console
5. In Google Cloud Console:
   - Click **Create Service Account**
   - Name: `github-actions-deploy`
   - Role: Select **Service Account User**
   - Click **Create Key** → **JSON**
   - Download the JSON key file (keep it secure!)

### Step 2: Grant Permissions in Play Console

1. Back in Play Console → **API access**
2. Find your new service account
3. Click **Grant access**
4. Select permissions:
   - **Release management** (required)
   - **Release to production** (if deploying to production)
   - **View app information** (required)
5. Select your app
6. Click **Apply**

### Step 3: Set up App Signing

#### Option A: Let Google manage signing (Recommended)
1. Go to **Setup → App signing**
2. Follow Google's app signing enrollment
3. Upload your existing keystore (if you have one)
4. Google will handle signing for distribution

#### Option B: Self-managed signing
1. Keep your keystore file secure
2. You'll need to add it to GitHub Secrets

### Step 4: Add GitHub Secrets

Go to your GitHub repository → Settings → Secrets and add:

#### Required Secrets:
- `PLAY_STORE_SERVICE_ACCOUNT_JSON` - The entire JSON content from Step 1
- `ANDROID_KEYSTORE` - Base64 encoded keystore (if self-signing)
- `ANDROID_KEYSTORE_PASSWORD` - Keystore password (if self-signing)
- `ANDROID_KEY_ALIAS` - Key alias (if self-signing)
- `ANDROID_KEY_PASSWORD` - Key password (if self-signing)

#### To encode keystore as base64:
```bash
base64 -i your-keystore.jks | tr -d '\n' > keystore-base64.txt
```

### Step 5: Update GitHub Workflow

See `.github/workflows/build.yml` for the complete workflow with Play Store deployment.

## Deployment Tracks

Google Play offers several deployment tracks:

- **Internal testing** - Limited to internal testers (fastest)
- **Closed testing (Alpha)** - Limited group of testers
- **Closed testing (Beta)** - Larger group of testers
- **Open testing** - Public beta
- **Production** - Full release

## Version Management

### Version Code
- Must increment with each upload
- Use GitHub run number: `${{ github.run_number }}`
- Or timestamp: `$(date +%s)`

### Version Name
- Human-readable version (e.g., "1.2.3")
- Extract from tag or pubspec.yaml

## Workflow Configuration

The workflow uses `r0adkll/upload-google-play@v1` action for deployment.

### Basic Upload
```yaml
- uses: r0adkll/upload-google-play@v1
  with:
    serviceAccountJsonPlainText: ${{ secrets.PLAY_STORE_SERVICE_ACCOUNT_JSON }}
    packageName: com.theparaglidingapp
    releaseFiles: app-release.aab
    track: internal
```

### With Release Notes
```yaml
- uses: r0adkll/upload-google-play@v1
  with:
    serviceAccountJsonPlainText: ${{ secrets.PLAY_STORE_SERVICE_ACCOUNT_JSON }}
    packageName: com.theparaglidingapp
    releaseFiles: app-release.aab
    track: production
    status: completed
    releaseNotes: |
      New features:
      - Feature 1
      - Feature 2
      Bug fixes:
      - Fix 1
```

## Testing the Setup

1. **Test with internal track first**
   ```yaml
   track: internal
   status: draft
   ```

2. **Verify in Play Console**
   - Check the internal testing track
   - Ensure the AAB was uploaded correctly

3. **Gradual rollout**
   ```yaml
   track: production
   status: inProgress
   userFraction: 0.1  # 10% rollout
   ```

## Troubleshooting

### Error: "APK specifies a version code that has already been used"
- Increment version code in pubspec.yaml
- Or use dynamic version code with run number

### Error: "The caller does not have permission"
- Check service account permissions in Play Console
- Ensure the app is selected in permissions

### Error: "Package name not found"
- Verify package name matches Play Console
- Ensure app is published (at least internal)

### Error: "Invalid JWT"
- Check service account JSON is correctly added to secrets
- Ensure no extra spaces or line breaks

## Security Best Practices

1. **Never commit secrets to repository**
2. **Use GitHub Secrets for all sensitive data**
3. **Restrict workflow triggers** to protected branches
4. **Enable branch protection** for main/production
5. **Use environment-specific tracks** (dev→internal, main→production)

## Example Release Process

1. Create release branch: `release/v1.2.3`
2. Update version in `pubspec.yaml`
3. Create PR to main
4. Merge PR (triggers workflow)
5. Workflow:
   - Builds signed AAB
   - Uploads to internal track
   - Creates GitHub release
6. Test in internal track
7. Promote to production in Play Console

## Useful Resources

- [Google Play Console Help](https://support.google.com/googleplay/android-developer)
- [Fastlane Alternative](https://docs.fastlane.tools/getting-started/android/release-deployment/)
- [GitHub Action: upload-google-play](https://github.com/r0adkll/upload-google-play)
- [Flutter Build Documentation](https://docs.flutter.dev/deployment/android)