# Wireless ADB Setup for ChromeOS - Complete Guide

This document provides a comprehensive guide for setting up wireless ADB debugging on ChromeOS for Flutter Android development.

> **This is the first-time setup guide.** For day-to-day use — the device id to pass to
> `-d`, reconnecting, screenshots, driving the UI, reading logs — the `run-app` skill is
> the operational source and is kept current. Come here when setting up a new machine or
> phone, or when pairing has broken.
>
> **Everything here needs the Bash sandbox disabled.** A sandboxed shell has no network
> interface at all, so any command reaching the phone fails with `Network is unreachable`
> — which reads as the phone being absent and is not. `No route to host` is the real
> network. See the `sandbox-setup` skill.

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

#### Platform tools

On this machine adb is **already installed** at `~/android-sdk/platform-tools/adb` and is
on `PATH` — check before installing anything:

```bash
which adb && adb --version
```

Expected output: `Android Debug Bridge version 1.0.41` or later. Only if that comes back
empty, install it:

```bash
mkdir -p ~/android-sdk && cd ~/android-sdk
wget https://dl.google.com/android/repository/platform-tools-latest-linux.zip
unzip platform-tools-latest-linux.zip
# then add ~/android-sdk/platform-tools to PATH
```

> Earlier versions of this guide installed a second copy under `~/platform-tools-new/`
> and prefixed every command with that path. Don't — a parallel adb means two servers
> competing for port 5037 and a device that appears in one and not the other.

## Wireless Connection Process

### Method 1: Android 11+ Built-in Wireless Debugging

#### Step 1: Get Device IP and Port

**Do not reuse an IP recorded anywhere — DHCP moves the phone.** The addresses in this
guide are examples from one past session, nothing more. Discover the live one instead:

```bash
adb mdns services | awk '/_adb-tls-connect/{print $NF}'   # connect port
adb mdns services | awk '/_adb-tls-pairing/{print $NF}'   # pairing port, only while the dialog is open
```

`adb mdns services` **does** work from this Crostini container (verified 2026-08-11); an
earlier claim that multicast cannot cross the NAT was wrong and cost real time. Falling
back to the on-screen values also works:

1. On Android device, go to **Developer options** → **Wireless debugging**
2. Note the **IP address & Port** at the top (e.g., `192.168.86.250:35933`)

#### Step 2: Pair Device (First Time Only)
1. Tap **"Pair device with pairing code"**
2. Note the 6-digit pairing code and pairing IP:port
3. On ChromeOS, run pairing command:
```bash
adb pair PAIRING_IP:PAIRING_PORT PAIRING_CODE

# Example:
adb pair 192.168.86.250:42889 593694
```

Expected output: `Successfully paired to 192.168.86.250:42889`

#### Step 3: Connect to Device
```bash
# Connect using the main IP and port (not the pairing port)
adb connect DEVICE_IP:DEVICE_PORT

# Example:
adb connect 192.168.86.250:35933
```

Expected output: `connected to 192.168.86.250:35933`

#### Step 4: Verify Connection
```bash
adb devices -l
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
Pixel 9 (mobile) • adb-52110DLAQ001UT-hkZkFs._adb-tls-connect._tcp • android-arm64 • Android 17 (API 37)
```

**Flutter wants its own device id, not the `IP:port` that `adb devices` prints**, and
once the phone is paired that id is stable across DHCP changes — which is why it, rather
than an address, is what you pass to `-d`. Always quote it.

Two things that look like an absent phone and are not: `flutter devices` listing only
Linux and Chrome (it can miss a transport `adb devices -l` sees — check both), and a
failing `adb connect` while `adb devices -l` shows the phone online on the next line.

### Deploy Flutter App Wirelessly

Use the project's runner rather than a bare `flutter run` — it handles the log file, the
pid file and the API keys:

```bash
bin/dev_run.sh -d "adb-52110DLAQ001UT-hkZkFs._adb-tls-connect._tcp" --background
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
adb kill-server

# Connect to device
adb connect $DEVICE_IP:$DEVICE_PORT

# Verify connection
if adb devices | grep -q "$DEVICE_IP:$DEVICE_PORT.*device"; then
    echo "✅ Successfully connected to $DEVICE_IP:$DEVICE_PORT"
    
    # Test connection
    DEVICE_MODEL=$(adb -s $DEVICE_IP:$DEVICE_PORT shell getprop ro.product.model)
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

adb pair $PAIRING_IP:$PAIRING_PORT $PAIRING_CODE

if [ $? -eq 0 ]; then
    echo "✅ Pairing successful!"
    echo
    read -p "Now enter the main connection IP: " DEVICE_IP
    read -p "Connection port: " DEVICE_PORT
    
    echo "Connecting to device..."
    adb connect $DEVICE_IP:$DEVICE_PORT
    
    if [ $? -eq 0 ]; then
        echo "✅ Device connected successfully!"
        echo "📱 Device details:"
        adb -s $DEVICE_IP:$DEVICE_PORT shell getprop ro.product.model
        
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
adb kill-server
adb start-server

# Check ADB server status
adb devices
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
adb -s DEVICE_IP:PORT shell pm list packages | head -1

# Verify developer options are still enabled
adb -s DEVICE_IP:PORT shell getprop ro.debuggable
```

### Performance Optimization

#### Connection Stability

Use Developer options → **"Stay awake"**, and keep the phone on a charger during test
sessions.

```bash
# Keep device awake during development
adb shell svc power stayon true
```

> **`settings put global wifi_sleep_policy 2` does not work** and was previously
> recommended here. It is a legacy setting that modern Android ignores: the phone still
> dozes (`DreamService[DozeService] mDozeScreenState=3`, then `Screen: 0, mDozeStatus: 2`),
> after which a `flutter run` session dies with "Lost connection to device". Setting it
> gives false confidence that the drop-outs are fixed.

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