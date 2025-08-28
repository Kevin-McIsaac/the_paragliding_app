# ChromeOS Flutter Development Setup - Complete Guide

This document provides a comprehensive guide for setting up professional Flutter development on ChromeOS with Android build capabilities and wireless debugging.

## Overview

This guide documents the complete setup process for Flutter development on ChromeOS, including:
- Android SDK configuration issues and solutions
- Wireless ADB debugging setup
- Development environment optimization
- Common issues and troubleshooting

## System Requirements

### ChromeOS Configuration
- ChromeOS with Linux development environment (Crostini) enabled
- Minimum 8GB RAM recommended (16GB preferred for Android builds)
- At least 20GB free storage for development tools and SDKs
- Developer mode enabled (optional, but recommended for advanced development)

### Network Requirements
- Stable WiFi connection for wireless debugging
- Same network access for development machine and Android device
- Preferably 5GHz WiFi for better performance

## Flutter Installation

### 1. Download and Install Flutter
```bash
# Create development directory
mkdir -p ~/development
cd ~/development

# Download Flutter stable channel
wget https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.32.8-stable.tar.xz

# Extract Flutter
tar xf flutter_linux_3.32.8-stable.tar.xz

# Add Flutter to PATH (add to ~/.bashrc for permanence)
export PATH="$HOME/development/flutter/bin:$PATH"

# Verify installation
flutter --version
```

### 2. Run Flutter Doctor
```bash
flutter doctor
```

Expected issues on fresh ChromeOS installation:
- ❌ Android toolchain missing
- ❌ Chrome executable not found (can be ignored for mobile development)
- ❌ Android Studio not configured

## Android Development Setup

### The Challenge: ChromeOS SDK Limitations

ChromeOS Linux containers have specific challenges for Android development:
1. **Limited system Android SDK** - Debian repositories provide minimal SDK
2. **Permission restrictions** - System SDK directories are read-only
3. **Memory constraints** - Linux container has limited resources
4. **Configuration conflicts** - Multiple tools competing for SDK paths

### Solution: Complete User-Controlled Android SDK

#### 1. Create Complete Android SDK
```bash
# Create SDK directory in user space
mkdir -p ~/android-sdk-complete
cd ~/android-sdk-complete

# Download complete Android command-line tools
wget https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip

# Extract and set up proper structure
unzip commandlinetools-linux-11076708_latest.zip
mkdir -p cmdline-tools/latest
mv cmdline-tools/{bin,lib,NOTICE.txt,source.properties} cmdline-tools/latest/

# Make tools executable
chmod +x cmdline-tools/latest/bin/*
```

#### 2. Install Essential Components
```bash
# Set environment for SDK operations
export ANDROID_HOME=~/android-sdk-complete
export ANDROID_SDK_ROOT=~/android-sdk-complete
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"

# Install platform tools
~/android-sdk-complete/cmdline-tools/latest/bin/sdkmanager "platform-tools"

# Install build tools and platforms
~/android-sdk-complete/cmdline-tools/latest/bin/sdkmanager "build-tools;34.0.0"
~/android-sdk-complete/cmdline-tools/latest/bin/sdkmanager "platforms;android-34"
~/android-sdk-complete/cmdline-tools/latest/bin/sdkmanager "platforms;android-35"

# Install NDK versions (both required for Flutter)
~/android-sdk-complete/cmdline-tools/latest/bin/sdkmanager "ndk;27.0.12077973"  # Plugin requirement
~/android-sdk-complete/cmdline-tools/latest/bin/sdkmanager "ndk;26.3.11579264"  # Build requirement

# Accept all licenses
yes | ~/android-sdk-complete/cmdline-tools/latest/bin/sdkmanager --licenses
```

#### 3. Configure Environment Permanently
```bash
# Add to ~/.bashrc for permanent configuration
cat >> ~/.bashrc << 'EOF'

# Android SDK Configuration - Complete SDK
export ANDROID_HOME=/home/kmcisaac/android-sdk-complete
export ANDROID_SDK_ROOT=/home/kmcisaac/android-sdk-complete
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
EOF

# Reload environment
source ~/.bashrc
```

#### 4. Configure Flutter for Android SDK
```bash
# Configure Flutter to use our complete SDK
flutter config --android-sdk $ANDROID_HOME

# Verify configuration
flutter doctor
```

Expected result after setup:
```
[✓] Flutter (Channel stable, 3.32.8)
[✓] Android toolchain - develop for Android devices (Android SDK version 34.0.0)
[✓] Linux toolchain - develop for Linux desktop
```

## Wireless ADB Setup

### 1. Download Modern Platform Tools
```bash
# Download latest platform tools with wireless pairing support
mkdir -p ~/platform-tools-new
cd ~/platform-tools-new
wget https://dl.google.com/android/repository/platform-tools-latest-linux.zip
unzip platform-tools-latest-linux.zip

# Verify wireless capability
~/platform-tools-new/platform-tools/adb --version
```

### 2. Android Device Configuration
1. **Enable Developer Options**: Settings → About phone → Tap "Build number" 7 times
2. **Enable USB Debugging**: Developer options → USB debugging → ON
3. **Enable Wireless Debugging**: Developer options → Wireless debugging → ON (Android 11+)

### 3. Pairing and Connection
```bash
# One-time pairing (Android 11+)
~/platform-tools-new/platform-tools/adb pair PAIRING_IP:PORT PAIRING_CODE

# Daily connection
~/platform-tools-new/platform-tools/adb connect DEVICE_IP:PORT

# Verify connection
~/platform-tools-new/platform-tools/adb devices
flutter devices
```

## Android Studio Integration

### 1. Install Android Studio
```bash
# Download Android Studio
cd ~/
wget https://redirector.gvt1.com/edgedl/android/studio/ide-zips/2024.2.1.13/android-studio-2024.2.1.13-linux.tar.gz

# Extract
tar -xzf android-studio-2024.2.1.13-linux.tar.gz
```

### 2. Create Desktop Launcher
```bash
# Create desktop entry
mkdir -p ~/.local/share/applications
cat > ~/.local/share/applications/android-studio.desktop << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Android Studio
Icon=/home/kmcisaac/android-studio/bin/studio.png
Exec=/home/kmcisaac/android-studio/bin/studio.sh
Comment=Android Studio IDE
Categories=Development;IDE;
Terminal=false
StartupWMClass=jetbrains-studio
EOF

chmod +x ~/.local/share/applications/android-studio.desktop
```

### 3. Configure Android Studio
1. **Launch Android Studio** from app launcher
2. **Configure SDK location**: File → Settings → Android SDK → SDK Location: `/home/kmcisaac/android-sdk-complete`
3. **Verify components**: Check that NDK and build tools are detected
4. **Import Flutter project**: Open → Navigate to Flutter project directory

## Project Configuration

### 1. Fix NDK Version Conflicts
Many Flutter projects have NDK version conflicts. Fix in `android/app/build.gradle.kts`:

```kotlin
android {
    namespace = "com.example.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"  // Specify exact version instead of flutter.ndkVersion
    
    // ... rest of configuration
}
```

### 2. Optimize Gradle Settings
In `android/gradle.properties`:
```properties
# Optimize for ChromeOS container memory constraints
org.gradle.jvmargs=-Xmx4G -XX:MaxMetaspaceSize=2G -XX:ReservedCodeCacheSize=256m
android.useAndroidX=true
android.enableJetifier=true

# Ensure correct SDK paths
android.sdk.home=/home/kmcisaac/android-sdk-complete
android.ndk.home=/home/kmcisaac/android-sdk-complete/ndk/27.0.12077973
```

### 3. Project SDK Configuration
In `android/local.properties`:
```properties
flutter.sdk=/path/to/flutter
sdk.dir=/home/kmcisaac/android-sdk-complete
android.sdk.home=/home/kmcisaac/android-sdk-complete
android.ndk.home=/home/kmcisaac/android-sdk-complete/ndk/27.0.12077973
```

## Development Workflow Scripts

### 1. Wireless Connection Script
**File**: `connect-android.sh`
```bash
#!/bin/bash
DEVICE_IP="192.168.86.250"
DEVICE_PORT="35933"

echo "Connecting to Android device..."
~/platform-tools-new/platform-tools/adb connect $DEVICE_IP:$DEVICE_PORT

if ~/platform-tools-new/platform-tools/adb devices | grep -q "device$"; then
    echo "✅ Device connected"
    flutter devices | grep -i android
else
    echo "❌ Connection failed"
fi
```

### 2. Development Environment Setup
**File**: `setup-flutter-env.sh`
```bash
#!/bin/bash
# Set up complete Flutter development environment

# Android SDK
export ANDROID_HOME=~/android-sdk-complete
export ANDROID_SDK_ROOT=~/android-sdk-complete
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"

# Flutter
export PATH="$HOME/development/flutter/bin:$PATH"

echo "Environment configured:"
echo "Flutter: $(flutter --version | head -1)"
echo "Android SDK: $ANDROID_HOME"
echo "Connected devices:"
flutter devices
```

### 3. Build and Deploy Script
**File**: `deploy-debug.sh`
```bash
#!/bin/bash
# Build and deploy debug APK wirelessly

set -e

# Configure environment
export ANDROID_HOME=~/android-sdk-complete
export ANDROID_SDK_ROOT=~/android-sdk-complete

DEVICE_IP="192.168.86.250:35933"

echo "Building debug APK..."
flutter build apk --debug --target-platform android-arm64

echo "Installing to device..."
~/platform-tools-new/platform-tools/adb -s $DEVICE_IP install -r build/app/outputs/flutter-apk/app-debug.apk

echo "Starting app..."
~/platform-tools-new/platform-tools/adb -s $DEVICE_IP shell am start -n com.example.app/com.example.app.MainActivity

echo "✅ App deployed and started!"
```

## Performance Optimization

### ChromeOS Container Optimization
```bash
# Increase container memory if possible (requires restart)
# In ChromeOS settings: Advanced → Developers → Linux development environment → Manage

# Monitor memory usage during builds
htop

# Clear build caches regularly
flutter clean
rm -rf ~/.gradle/caches/
```

### Build Performance
```bash
# Use specific architecture for faster builds
flutter build apk --debug --target-platform android-arm64

# Skip unnecessary targets
flutter build apk --debug --no-tree-shake-icons

# Parallel builds (gradle.properties)
org.gradle.parallel=true
org.gradle.daemon=true
```

### Network Optimization
- Use 5GHz WiFi when possible
- Keep devices close to router
- Consider dedicated development network

## Troubleshooting Common Issues

### 1. "NDK not found" or NDK version conflicts
**Problem**: Flutter plugins require different NDK versions
**Solution**: Install both required NDK versions and specify in build.gradle.kts

### 2. "SDK directory not writable"
**Problem**: Trying to use system SDK directories
**Solution**: Use complete user-controlled SDK at `~/android-sdk-complete`

### 3. Gradle daemon crashes
**Problem**: Memory constraints in ChromeOS container
**Solution**: Reduce Gradle memory allocation or use Android Studio

### 4. Wireless device not detected
**Problem**: ADB connection issues or network problems
**Solution**: Check wireless debugging settings, restart ADB, verify network

### 5. Build timeouts
**Problem**: Large builds exceeding time limits
**Solution**: Use Android Studio for builds, or external build server

## Advanced Development Setup

### Multiple Device Management
```bash
# List all devices
~/platform-tools-new/platform-tools/adb devices

# Deploy to specific device
flutter run -d DEVICE_ID

# Multiple wireless connections
~/platform-tools-new/platform-tools/adb connect 192.168.1.100:5555
~/platform-tools-new/platform-tools/adb connect 192.168.1.101:5555
```

### Remote Development
```bash
# Use VS Code remote development
code --remote ssh-remote+user@server /path/to/project

# Sync with external build server
rsync -avz project/ server:~/project/
ssh server "cd ~/project && flutter build apk"
scp server:~/project/build/app/outputs/flutter-apk/app-debug.apk .
```

### Performance Monitoring
```bash
# Monitor Android device performance
~/platform-tools-new/platform-tools/adb shell top

# Flutter performance tools
flutter analyze
flutter test
dart analyze
```

## Best Practices

### Development Workflow
1. **Start with Linux build** for rapid iteration
2. **Use hot reload** for UI development
3. **Test on Android** for platform-specific features
4. **Use wireless ADB** to eliminate cable management
5. **Regular clean builds** to avoid cache issues

### Code Organization
- Keep platform-specific code in appropriate directories
- Use feature flags for experimental features
- Maintain separate build configurations for debug/release

### Version Control
- Use `.gitignore` to exclude build artifacts
- Include configuration files but not sensitive data
- Document setup requirements in README

### Maintenance
- Regularly update Flutter and Android SDK
- Monitor for new NDK requirements in plugin updates
- Keep wireless ADB scripts updated with current device IPs

## Summary

This setup provides a complete Flutter development environment on ChromeOS with:
- ✅ **Full Android build capability** with proper NDK support
- ✅ **Wireless debugging** without USB cable dependencies  
- ✅ **Android Studio integration** for comprehensive development
- ✅ **Optimized for ChromeOS** container resource constraints
- ✅ **Automated deployment scripts** for efficient workflow

The key to success on ChromeOS is using a complete, user-controlled Android SDK that avoids system limitations and configuration conflicts. With this setup, ChromeOS becomes a fully capable mobile development platform.