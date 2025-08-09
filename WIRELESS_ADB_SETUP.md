# Wireless ADB Setup for ChromeOS - Complete Guide

This document provides a comprehensive guide for setting up wireless ADB debugging on ChromeOS for Flutter Android development.

## Overview

Wireless ADB allows you to debug and deploy Android apps over WiFi without USB cables. This is especially useful for ChromeOS development where USB passthrough can be limited.

## Prerequisites

- ChromeOS with Linux development environment enabled
- Android device with Developer Options enabled
- Both devices on the same WiFi network
- Android 11+ (recommended for built-in wireless debugging)

## Initial Setup

### 1. Android Device Configuration

#### Enable Developer Options
1. Go to **Settings** → **About phone**
2. Find **Build number** (may be under Software information)
3. Tap **Build number** 7 times rapidly
4. You'll see "You are now a developer!"

#### Enable USB Debugging and Wireless Debugging
1. Go to **Settings** → **System** → **Developer options**
2. Toggle ON **USB debugging**
3. Toggle ON **Wireless debugging** (Android 11+ only)
4. Optionally enable **Stay awake** (keeps screen on while charging)

### 2. ChromeOS Platform Tools Setup

#### Download Latest Platform Tools
```bash
# Create directory for new platform tools
mkdir -p ~/platform-tools-new
cd ~/platform-tools-new

# Download latest platform tools with wireless pairing support
wget https://dl.google.com/android/repository/platform-tools-latest-linux.zip

# Extract tools
unzip platform-tools-latest-linux.zip

# Verify installation
~/platform-tools-new/platform-tools/adb --version
```

Expected output: `Android Debug Bridge version 1.0.41` or later

## Wireless Connection Process

### Method 1: Android 11+ Built-in Wireless Debugging

#### Step 1: Get Device IP and Port
1. On Android device, go to **Developer options** → **Wireless debugging**
2. Note the **IP address & Port** at the top (e.g., `192.168.86.250:35933`)

#### Step 2: Pair Device (First Time Only)
1. Tap **"Pair device with pairing code"**
2. Note the 6-digit pairing code and pairing IP:port
3. On ChromeOS, run pairing command:
```bash
~/platform-tools-new/platform-tools/adb pair PAIRING_IP:PAIRING_PORT PAIRING_CODE

# Example:
~/platform-tools-new/platform-tools/adb pair 192.168.86.250:42889 593694
```

Expected output: `Successfully paired to 192.168.86.250:42889`

#### Step 3: Connect to Device
```bash
# Connect using the main IP and port (not the pairing port)
~/platform-tools-new/platform-tools/adb connect DEVICE_IP:DEVICE_PORT

# Example:
~/platform-tools-new/platform-tools/adb connect 192.168.86.250:35933
```

Expected output: `connected to 192.168.86.250:35933`

#### Step 4: Verify Connection
```bash
~/platform-tools-new/platform-tools/adb devices -l
```

Expected output should show your device:
```
List of devices attached
192.168.86.250:35933   device product:tokay model:Pixel_9 device:tokay transport_id:37
```

### Method 2: Legacy Wireless ADB (Android 10 and below)

#### Step 1: Initial USB Connection (Required)
1. Connect device via USB cable first
2. Ensure USB debugging is enabled
3. Accept debugging authorization on device

#### Step 2: Enable TCP/IP Mode
```bash
# Switch to TCP/IP mode on port 5555
adb tcpip 5555

# Disconnect USB cable
```

#### Step 3: Get Device IP Address
```bash
# Find IP address (or check in device WiFi settings)
adb shell ip addr show wlan0
```

#### Step 4: Connect Wirelessly
```bash
adb connect DEVICE_IP:5555
```

## Flutter Integration

### Verify Flutter Recognizes Device
```bash
flutter devices
```

Expected output should include your wireless device:
```
Pixel 9 (mobile) • 192.168.86.250:35933 • android-arm64 • Android 16 (API 36)
```

### Deploy Flutter App Wirelessly
```bash
flutter run -d 192.168.86.250:35933
```

## Automated Connection Scripts

### Daily Connection Script
**File**: `connect-wireless-adb.sh`
```bash
#!/bin/bash
# Reconnect to wireless Android device

DEVICE_IP="192.168.86.250"
DEVICE_PORT="35933"  # Update this when device port changes

echo "Connecting to Android device wirelessly..."

# Kill any existing ADB server
~/platform-tools-new/platform-tools/adb kill-server

# Connect to device
~/platform-tools-new/platform-tools/adb connect $DEVICE_IP:$DEVICE_PORT

# Verify connection
if ~/platform-tools-new/platform-tools/adb devices | grep -q "$DEVICE_IP:$DEVICE_PORT.*device"; then
    echo "✅ Successfully connected to $DEVICE_IP:$DEVICE_PORT"
    
    # Test connection
    DEVICE_MODEL=$(~/platform-tools-new/platform-tools/adb -s $DEVICE_IP:$DEVICE_PORT shell getprop ro.product.model)
    echo "📱 Device: $DEVICE_MODEL"
    
    # Check if Flutter recognizes device
    if flutter devices | grep -q "$DEVICE_IP:$DEVICE_PORT"; then
        echo "✅ Flutter recognizes wireless device"
    else
        echo "⚠️  Flutter may need restart to recognize device"
    fi
else
    echo "❌ Failed to connect to device"
    echo "Check that:"
    echo "  - Device is on same WiFi network"
    echo "  - Wireless debugging is enabled"
    echo "  - IP address and port are correct"
fi
```

### Pairing Helper Script
**File**: `pair-android-device.sh`
```bash
#!/bin/bash
# Helper script for pairing new Android devices

echo "📱 Android Wireless ADB Pairing Helper"
echo "======================================"
echo
echo "1. On your Android device:"
echo "   - Go to Developer options → Wireless debugging"
echo "   - Tap 'Pair device with pairing code'"
echo
echo "2. Enter the details shown on your device:"

read -p "Pairing IP address: " PAIRING_IP
read -p "Pairing port: " PAIRING_PORT  
read -p "6-digit pairing code: " PAIRING_CODE

echo
echo "Pairing with device..."

~/platform-tools-new/platform-tools/adb pair $PAIRING_IP:$PAIRING_PORT $PAIRING_CODE

if [ $? -eq 0 ]; then
    echo "✅ Pairing successful!"
    echo
    read -p "Now enter the main connection IP: " DEVICE_IP
    read -p "Connection port: " DEVICE_PORT
    
    echo "Connecting to device..."
    ~/platform-tools-new/platform-tools/adb connect $DEVICE_IP:$DEVICE_PORT
    
    if [ $? -eq 0 ]; then
        echo "✅ Device connected successfully!"
        echo "📱 Device details:"
        ~/platform-tools-new/platform-tools/adb -s $DEVICE_IP:$DEVICE_PORT shell getprop ro.product.model
        
        echo
        echo "💡 Save these details for future connections:"
        echo "   IP: $DEVICE_IP"
        echo "   Port: $DEVICE_PORT"
    else
        echo "❌ Connection failed"
    fi
else
    echo "❌ Pairing failed"
fi
```

## Troubleshooting

### Connection Issues

#### Device Not Found
```bash
# Check if device is on same network
ping DEVICE_IP

# Restart ADB server
~/platform-tools-new/platform-tools/adb kill-server
~/platform-tools-new/platform-tools/adb start-server

# Check ADB server status
~/platform-tools-new/platform-tools/adb devices
```

#### Connection Refused
- **Check wireless debugging is enabled** on device
- **Verify IP address and port** (they change when wireless debugging is toggled)
- **Check WiFi network** - both devices must be on same network
- **Restart wireless debugging** on device

#### Pairing Code Expired
- Pairing codes expire after 1-2 minutes
- Generate new pairing code on device
- Re-run pairing command immediately

#### Permission Issues
```bash
# On device, you may need to re-accept debugging authorization
# Look for "Allow USB debugging?" popup
# Check "Always allow from this computer"
```

### Flutter Integration Issues

#### Device Not Recognized by Flutter
```bash
# Restart Flutter daemon
flutter daemon --version

# Clear Flutter cache
flutter clean
flutter pub get

# Verify ADB path in Flutter
flutter doctor -v
```

#### Deployment Fails
```bash
# Check device is authorized for app installation
~/platform-tools-new/platform-tools/adb -s DEVICE_IP:PORT shell pm list packages | head -1

# Verify developer options are still enabled
~/platform-tools-new/platform-tools/adb -s DEVICE_IP:PORT shell getprop ro.debuggable
```

### Performance Optimization

#### Connection Stability
```bash
# Keep device awake during development
~/platform-tools-new/platform-tools/adb shell svc power stayon true

# Disable WiFi power saving (may help with connection stability)
~/platform-tools-new/platform-tools/adb shell settings put global wifi_sleep_policy 2
```

#### Network Optimization
- Use 5GHz WiFi when possible for better performance
- Ensure strong WiFi signal on both devices
- Consider using dedicated development WiFi network

## Security Considerations

### Network Security
- Wireless debugging should only be used on trusted networks
- Turn off wireless debugging when not actively developing
- Consider using VPN for additional security on public networks

### Device Security
- "Always allow from this computer" creates permanent authorization
- Revoke debugging authorization when selling/disposing device
- Monitor connected devices periodically

### Development Network
- Consider separate WiFi network for development
- Use strong WPA3 encryption
- Regularly update device and development tools

## Best Practices

### Daily Development Workflow
1. **Enable wireless debugging** on device
2. **Run connection script** to establish ADB connection
3. **Verify with `flutter devices`** that device is recognized
4. **Deploy with `flutter run -d DEVICE_IP:PORT`**
5. **Disable wireless debugging** when done

### Connection Management
- **Save device IP and port** in connection scripts
- **Update scripts when port changes** (happens when wireless debugging is toggled)
- **Use device model/serial for identification** in multi-device setups

### Performance Tips
- **Keep devices charged** during long debugging sessions
- **Use dedicated development WiFi** for better performance
- **Close unnecessary apps** on Android device during debugging
- **Monitor logcat output** for performance issues

## Integration with IDEs

### Android Studio
1. **Detect wireless device** automatically after ADB connection
2. **Select device** from device dropdown in toolbar
3. **Deploy directly** using Run button

### VS Code
1. **Install Flutter extension**
2. **Use Command Palette** → "Flutter: Select Device"
3. **Choose wireless device** from list
4. **Debug with F5** or Run without debugging

### IntelliJ IDEA
1. **Configure Flutter SDK** in project settings
2. **Select wireless device** in run configuration
3. **Deploy with standard run controls**

## Summary

Wireless ADB debugging provides a seamless development experience by eliminating USB cable dependencies. Key points:

- **Modern Android devices** (11+) have built-in wireless debugging
- **Pairing is required once** per development machine
- **Connection ports change** when wireless debugging is toggled
- **Both devices must be on same WiFi network**
- **Scripts automate daily connection workflow**
- **Flutter integrates seamlessly** with wireless ADB

This setup enables professional mobile development directly on ChromeOS with full wireless debugging capabilities.