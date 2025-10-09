#!/bin/bash
# Deploy The Paragliding App to Pixel 9 wirelessly
# Complete Android SDK configuration script

set -e  # Exit on any error

echo "🚀 Deploying The Paragliding App to Pixel 9 wirelessly..."

# Set Android SDK environment
export ANDROID_HOME=/home/kmcisaac/android-sdk-complete
export ANDROID_SDK_ROOT=/home/kmcisaac/android-sdk-complete
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"

echo "📱 Checking Pixel 9 connection..."
if ~/platform-tools-new/platform-tools/adb -s 192.168.86.250:34695 shell getprop ro.product.model | grep -q "Pixel 9"; then
    echo "✅ Pixel 9 connected wirelessly!"
else
    echo "❌ Pixel 9 not connected. Please reconnect."
    exit 1
fi

echo "🏗️ Building APK for ARM64..."
flutter build apk --debug --target-platform android-arm64 --dart-define=flutter.flutter_map.unblockOSM="Our tile servers are not."

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    echo "📦 Installing APK to Pixel 9..."
    ~/platform-tools-new/platform-tools/adb -s 192.168.86.250:34695 install -r build/app/outputs/flutter-apk/app-debug.apk
    
    if [ $? -eq 0 ]; then
        echo "🎉 App installed successfully!"
        echo "🚀 Starting app on Pixel 9..."
        ~/platform-tools-new/platform-tools/adb -s 192.168.86.250:34695 shell am start -n com.theparaglidingapp/com.theparaglidingapp.MainActivity
        echo "✅ The Paragliding App is now running on your Pixel 9!"
    else
        echo "❌ Failed to install APK"
        exit 1
    fi
else
    echo "❌ Build failed"
    exit 1
fi