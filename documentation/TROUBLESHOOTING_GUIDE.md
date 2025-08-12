# Flutter Android Development Troubleshooting Guide

This guide provides solutions to common issues encountered when developing Flutter apps for Android on ChromeOS.

## Quick Reference

### Environment Variables Check
```bash
echo "ANDROID_HOME: $ANDROID_HOME"
echo "ANDROID_SDK_ROOT: $ANDROID_SDK_ROOT"
echo "PATH contains SDK: $(echo $PATH | grep android-sdk-complete)"
```

### Connection Status Check
```bash
# ADB devices
~/platform-tools-new/platform-tools/adb devices

# Flutter devices
flutter devices

# Test connection
~/platform-tools-new/platform-tools/adb shell getprop ro.product.model
```

## Common Build Issues

### 1. NDK Version Conflicts

#### Symptoms
```
Your project is configured with Android NDK 26.3.11579264, but the following plugin(s) depend on a different Android NDK version:
- file_picker requires Android NDK 27.0.12077973
- sqflite_android requires Android NDK 27.0.12077973
```

#### Root Cause
Flutter plugins require NDK 27.0.12077973, but build system defaults to older version.

#### Solution
**File**: `android/app/build.gradle.kts`
```kotlin
android {
    namespace = "com.example.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"  // Change from flutter.ndkVersion
    // ... rest of configuration
}
```

**Verify Both NDK Versions Installed**:
```bash
~/android-sdk-complete/cmdline-tools/latest/bin/sdkmanager --list_installed | grep ndk
```

Should show both:
- `ndk;26.3.11579264`
- `ndk;27.0.12077973`

### 2. SDK Directory Not Writable

#### Symptoms
```
The SDK directory is not writable (/usr/lib/android-sdk)
Failed to install NDK: permission denied
```

#### Root Cause
Using system Android SDK which has restricted permissions.

#### Solution
Verify using complete user-controlled SDK:
```bash
# Check environment
echo $ANDROID_HOME
# Should be: /home/kmcisaac/android-sdk-complete

# If not, set correctly
export ANDROID_HOME=/home/kmcisaac/android-sdk-complete
export ANDROID_SDK_ROOT=/home/kmcisaac/android-sdk-complete

# Verify Flutter is using correct SDK
flutter config --android-sdk $ANDROID_HOME
flutter doctor -v
```

### 3. Gradle Daemon Crashes

#### Symptoms
```
Gradle build daemon disappeared unexpectedly (it may have been killed or may have crashed)
The message received from the daemon indicates that the daemon has disappeared.
```

#### Root Cause
ChromeOS container memory limitations causing Gradle daemon to be killed.

#### Solution A: Reduce Memory Usage
**File**: `android/gradle.properties`
```properties
# Reduce memory allocation
org.gradle.jvmargs=-Xmx4G -XX:MaxMetaspaceSize=2G -XX:ReservedCodeCacheSize=256m
```

#### Solution B: Use Android Studio
Android Studio manages Gradle more efficiently:
1. Launch Android Studio
2. Open your Flutter project
3. Select your wireless device
4. Click Run button

#### Solution C: Build on External Server
```bash
# Upload project to server with more resources
rsync -avz --exclude build/ project/ server:~/project/
ssh server "cd ~/project && flutter build apk --debug"
scp server:~/project/build/app/outputs/flutter-apk/app-debug.apk .
```

### 4. Configuration File Conflicts

#### Symptoms
```
local.properties keeps getting reset
Android Studio creates ~/Android/Sdk directory
Wrong SDK path in build output
```

#### Root Cause
Multiple configuration sources competing for SDK paths.

#### Complete Reset Solution
```bash
# 1. Remove conflicting directories
rm -rf ~/Android/

# 2. Clear all caches
flutter clean
rm -rf ~/.gradle/daemon/
rm -rf ~/.gradle/caches/
rm -rf android/.gradle/

# 3. Reset Android Studio config
rm -rf ~/.config/Google/AndroidStudio*

# 4. Set global Gradle config
mkdir -p ~/.gradle
cat > ~/.gradle/gradle.properties << EOF
android.sdk.home=/home/kmcisaac/android-sdk-complete
android.ndk.home=/home/kmcisaac/android-sdk-complete/ndk/27.0.12077973
sdk.dir=/home/kmcisaac/android-sdk-complete
EOF

# 5. Make project config read-only
chmod 444 android/local.properties
```

## Wireless ADB Issues

### 1. Device Not Found

#### Symptoms
```
List of devices attached
[empty or only shows emulator]
```

#### Diagnostic Steps
```bash
# 1. Check if device is on network
ping DEVICE_IP

# 2. Check ADB server status
~/platform-tools-new/platform-tools/adb kill-server
~/platform-tools-new/platform-tools/adb start-server

# 3. Try manual connection
~/platform-tools-new/platform-tools/adb connect DEVICE_IP:PORT
```

#### Common Solutions
1. **Check Wireless Debugging**: Settings → Developer options → Wireless debugging → ON
2. **Check Network**: Both devices on same WiFi
3. **Restart Wireless Debugging**: Toggle OFF and ON
4. **Update IP/Port**: Connection details change when wireless debugging is toggled

### 2. Connection Refused

#### Symptoms
```
failed to connect to 'IP:PORT': Connection refused
```

#### Solutions
1. **Get Current IP/Port**: Check wireless debugging settings for current values
2. **Re-pair Device**: Use `adb pair` with new pairing code
3. **Check Firewall**: Ensure no firewall blocking ADB ports
4. **Try Different Port**: Some devices use multiple ports

### 3. Pairing Failures

#### Symptoms
```
failed to pair to 'IP:PORT': connection failed
pairing code expired
```

#### Solutions
1. **Generate New Code**: Tap "Pair device with pairing code" again
2. **Act Quickly**: Pairing codes expire in 1-2 minutes
3. **Check IP/Port**: Use pairing IP:port, not connection IP:port
4. **Try Multiple Times**: Sometimes requires several attempts

## Flutter-Specific Issues

### 1. Flutter Not Recognizing Device

#### Symptoms
```
$ flutter devices
No devices detected
```

But ADB shows device connected:
```
$ adb devices
192.168.86.250:35933    device
```

#### Solutions
```bash
# 1. Restart Flutter daemon
flutter daemon --version

# 2. Check Flutter ADB
flutter config --android-sdk $ANDROID_HOME
flutter doctor -v

# 3. Verify device authorization
~/platform-tools-new/platform-tools/adb -s DEVICE_IP:PORT shell echo "test"
```

### 2. Deployment Failures

#### Symptoms
```
Error: ADB exited with code 1
Installation failed with message INSTALL_FAILED_USER_RESTRICTED
```

#### Solutions
1. **Check Unknown Sources**: Enable installation from unknown sources
2. **Check Storage Space**: Ensure device has sufficient storage
3. **Reinstall App**: Use `-r` flag for reinstall
   ```bash
   ~/platform-tools-new/platform-tools/adb install -r app.apk
   ```
4. **Clear App Data**: Uninstall previous version first

### 3. Hot Reload Not Working

#### Symptoms
Hot reload doesn't update app on device.

#### Solutions
1. **Check Connection Stability**: Weak WiFi can break hot reload
2. **Restart Flutter**: `flutter run` again
3. **Full Restart**: Use `R` in Flutter console for full restart
4. **Check Logs**: Look for connection errors in `flutter logs`

## Performance Issues

### 1. Slow Builds

#### Symptoms
Gradle builds taking >10 minutes or timing out.

#### Solutions
```bash
# 1. Enable Gradle parallel builds
echo "org.gradle.parallel=true" >> android/gradle.properties

# 2. Use specific architecture
flutter build apk --debug --target-platform android-arm64

# 3. Skip unnecessary processing
flutter build apk --debug --no-tree-shake-icons

# 4. Clean and retry
flutter clean
flutter pub get
```

### 2. Memory Issues During Build

#### Symptoms
```
OutOfMemoryError: Java heap space
Gradle daemon stopped unexpectedly
```

#### Solutions
1. **Close Unnecessary Apps** in ChromeOS
2. **Increase Container Memory** (ChromeOS settings)
3. **Use External Build Server** for resource-intensive builds
4. **Build Incrementally**: Focus on specific architectures/configurations

## Network and Connectivity Issues

### 1. Intermittent Wireless Connection

#### Symptoms
Device randomly disconnects during development.

#### Solutions
```bash
# 1. Disable WiFi power saving
~/platform-tools-new/platform-tools/adb shell settings put global wifi_sleep_policy 2

# 2. Keep device awake
~/platform-tools-new/platform-tools/adb shell svc power stayon true

# 3. Use 5GHz network when possible
# 4. Keep devices close to router
```

### 2. Poor Performance Over Wireless

#### Symptoms
Slow app deployment, laggy debugging.

#### Solutions
1. **Check Network Speed**: Use speed test on both devices
2. **Reduce Network Traffic**: Close streaming apps, downloads
3. **Use Dedicated Development Network**: Set up separate WiFi for development
4. **Consider USB Fallback**: For intensive debugging sessions

## SDK and Tool Issues

### 1. Outdated Platform Tools

#### Symptoms
```
adb pair command not found
older ADB version doesn't support wireless
```

#### Solutions
```bash
# Download latest platform tools
mkdir -p ~/platform-tools-latest
cd ~/platform-tools-latest
wget https://dl.google.com/android/repository/platform-tools-latest-linux.zip
unzip platform-tools-latest-linux.zip

# Verify version
~/platform-tools-latest/platform-tools/adb --version
# Should be 1.0.41 or later for wireless support
```

### 2. License Issues

#### Symptoms
```
Failed to install the following SDK components:
License not accepted
```

#### Solutions
```bash
# Accept all licenses
yes | ~/android-sdk-complete/cmdline-tools/latest/bin/sdkmanager --licenses

# Or use Flutter
yes | flutter doctor --android-licenses
```

### 3. SDK Component Missing

#### Symptoms
```
Package 'build-tools;34.0.0' is not installed
NDK package not found
```

#### Solutions
```bash
# List available packages
~/android-sdk-complete/cmdline-tools/latest/bin/sdkmanager --list

# Install missing components
~/android-sdk-complete/cmdline-tools/latest/bin/sdkmanager "build-tools;34.0.0"
~/android-sdk-complete/cmdline-tools/latest/bin/sdkmanager "ndk;27.0.12077973"

# Verify installation
~/android-sdk-complete/cmdline-tools/latest/bin/sdkmanager --list_installed
```

## Emergency Recovery Procedures

### 1. Complete Environment Reset

When everything is broken:
```bash
# 1. Kill all processes
pkill -f flutter
pkill -f gradle
pkill -f adb

# 2. Remove all caches
rm -rf ~/.gradle/
rm -rf ~/.pub-cache/
flutter clean

# 3. Reset SDK configuration
rm -rf ~/Android/
export ANDROID_HOME=/home/kmcisaac/android-sdk-complete
flutter config --android-sdk $ANDROID_HOME

# 4. Restart from clean state
flutter doctor
flutter pub get
```

### 2. ADB Reset

When ADB is completely broken:
```bash
# 1. Kill all ADB processes
sudo pkill -f adb

# 2. Remove ADB server files
rm -f ~/.android/adbkey*

# 3. Restart ADB server
~/platform-tools-new/platform-tools/adb kill-server
~/platform-tools-new/platform-tools/adb start-server

# 4. Re-pair device
~/platform-tools-new/platform-tools/adb pair IP:PORT CODE
```

### 3. Project Reset

When project configuration is corrupted:
```bash
# 1. Clean all build artifacts
flutter clean
rm -rf build/
rm -rf android/.gradle/
rm -rf .dart_tool/

# 2. Reset configuration files
git checkout android/local.properties
git checkout android/gradle.properties

# 3. Regenerate Flutter files
flutter pub get
flutter pub deps

# 4. Test basic functionality
flutter doctor
flutter devices
```

## Prevention Tips

### Regular Maintenance
1. **Weekly**: Update Flutter, check for SDK updates
2. **Before Major Development**: Run `flutter clean` and rebuild
3. **Monthly**: Clear caches (`~/.gradle/caches/`)
4. **After ChromeOS Updates**: Verify development environment

### Best Practices
1. **Use Version Control**: Commit working configurations
2. **Document Device IPs**: Keep record of wireless ADB connection details
3. **Backup Scripts**: Save working connection and build scripts
4. **Monitor Resources**: Watch memory usage during builds
5. **Test Regularly**: Verify wireless ADB connection daily

### Environment Monitoring
```bash
# Create monitoring script
cat > ~/check-dev-env.sh << 'EOF'
#!/bin/bash
echo "=== Flutter Development Environment Status ==="
echo "Flutter: $(flutter --version | head -1)"
echo "Android SDK: $ANDROID_HOME"
echo "Wireless Device: $(~/platform-tools-new/platform-tools/adb devices | grep -v "List" | head -1)"
echo "Disk Space: $(df -h ~ | tail -1 | awk '{print $4}') available"
echo "Memory: $(free -h | grep Mem | awk '{print $7}') available"
EOF

chmod +x ~/check-dev-env.sh
```

This troubleshooting guide should help resolve most issues encountered during Flutter Android development on ChromeOS. For persistent issues, consider using Android Studio or an external development server for builds while maintaining wireless debugging for deployment and testing.