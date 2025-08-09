#!/bin/bash
# Flutter Android Development Script with Complete SDK
# This ensures Flutter uses our complete Android SDK instead of the system one

# Set Android SDK environment variables
export ANDROID_HOME=/home/kmcisaac/android-sdk-complete
export ANDROID_SDK_ROOT=/home/kmcisaac/android-sdk-complete
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"

# Update local.properties to use our SDK
echo "flutter.sdk=/home/kmcisaac/flutter" > android/local.properties
echo "sdk.dir=/home/kmcisaac/android-sdk-complete" >> android/local.properties
echo "flutter.buildMode=debug" >> android/local.properties
echo "flutter.versionName=1.0.0" >> android/local.properties
echo "flutter.versionCode=1" >> android/local.properties

# Run Flutter command with arguments
flutter "$@" --dart-define=flutter.flutter_map.unblockOSM="Our tile servers are not."