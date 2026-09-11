# Wireless ADB Setup for ChromeOS - Complete Guide

This document provides a comprehensive guide for setting up wireless ADB debugging on ChromeOS for Flutter Android development.

> **This is the first-time setup guide.** For day-to-day use — the device id to pass to
> `-d`, reconnecting, screenshots, driving the UI, reading logs — the `run-app` skill is
> the operational source and is kept current. Come here when setting up a new machine or
> phone, or when pairing has broken.
>
> **Under Claude Code, everything here needs the Bash sandbox disabled.** A sandboxed
> shell there has no network interface at all, so any command reaching the phone fails
> with `Network is unreachable` — which reads as the phone being absent and is not.
> `No route to host` is the real network. See the `sandbox-setup` skill.
>
> **Under DSH that is not true** (verified 2026-09-12): with the `workspace-write` sandbox
> on, `adb mdns services`, `adb pair`, `adb connect`, `adb devices -l` and
> `flutter devices` all reached the phone. Try a sandboxed call first; only escalate if it
> actually fails.

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

> **Check the *version*, not just that `which adb` answered.** Debian also ships an adb at
> `/usr/bin/adb`, and in this container it is **29.0.6** — old enough to predate
> `adb mdns`, which fails as `adb: unknown command mdns`. `apt` has no newer candidate, so
> the fix is PATH order or a symlink, never an upgrade. The current platform-tools build is
> **37.0.0**:
>
> ```bash
> /home/kmcisaac/android-sdk/platform-tools/adb version   # want 1.0.41 / 37.x, not 29.0.6
> ```
>
> In an **interactive** shell `~/.bashrc` already prepends platform-tools, so bare `adb` is
> correct. Agent shells are non-interactive `bash -c` and never read `.bashrc`, so they
> would otherwise get the 29.0.6 one (the `run-app` skill carries the export for that case).
>
> **On this machine the gap is closed at the system level** (2026-09-12) by a symlink into
> `/usr/local/bin`, which precedes `/usr/bin` on PATH:
>
> ```bash
> sudo ln -sf /home/kmcisaac/android-sdk/platform-tools/adb /usr/local/bin/adb
> command -v adb && adb version        # expect /usr/local/bin/adb, 37.x
> ```
>
> Afterwards bare `adb` is 37.0.0 in **every** shell, non-interactive ones included, so the
> export in the `run-app` skill is belt-and-braces rather than load-bearing. An **agent
> shell cannot create it** (no working `sudo` — see `CLAUDE.md` item 3), so this is a
> one-time job for the human in their own terminal; re-run it if `command -v adb` ever
> points at `/usr/bin` again. The link survives `sdkmanager` updates of platform-tools but
> **dangles if `~/android-sdk/platform-tools` is deleted**, and
> `sudo rm /usr/local/bin/adb` reverses it.
>
> **Don't "tidy up" by removing the Debian one.** `apt remove android-sdk-platform-tools`
> removes only the meta package — `adb` is an automatic dependency and stays, still
> shadowing — and following it with `autoremove` also takes **`sqlite3`**, **`graphviz`**,
> `f2fs-tools` and `/lib/udev/rules.d/51-android.rules`, which is the **only** udev rules
> file on the box (Google's platform-tools ships none, so USB debugging permissions go with
> it). If you must remove it: `apt-mark manual sqlite3 graphviz f2fs-tools` first, then
> `apt autoremove --dry-run` before letting it act. Left installed it is inert, as long as
> PATH is right.

> Earlier versions of this guide installed a second copy under `~/platform-tools-new/`
> and prefixed every command with that path. Don't — a parallel adb means two servers
> competing for port 5037 and a device that appears in one and not the other.

## Wireless Connection Process

### Method 1: Android 11+ Built-in Wireless Debugging

#### Step 1: Get Device IP and Port

**Do not reuse an IP recorded anywhere — DHCP moves the phone.** The addresses in this
guide are examples from one past session, nothing more. Discover the live one instead:

```bash
ADB="$HOME/android-sdk/platform-tools/adb"   # bare `adb` may be the 29.0.6 system one
"$ADB" mdns services | awk '/_adb-tls-connect/{print $NF}'   # connect port
"$ADB" mdns services | awk '/_adb-tls-pairing/{print $NF}'   # pairing port, only while the dialog is open
```

`adb mdns services` **does** work from this Crostini container (verified 2026-08-11); an
earlier claim that multicast cannot cross the NAT was wrong and cost real time.

**It is also flaky, which is not the same as absent** (verified 2026-09-12): it returned an
empty list on 4 of 6 calls, twice in a row, and found the phone on the next attempt. Retry
two or three times before concluding the phone is off the network.

Falling back to the on-screen values also works:

1. On Android device, go to **Developer options** → **Wireless debugging**
2. Note the **IP address & Port** at the top (e.g., `192.168.86.144:44457`)

#### Step 2: Pair Device (First Time Only)
1. Tap **"Pair device with pairing code"**
2. Note the 6-digit pairing code and pairing IP:port
3. On ChromeOS, run pairing command:
```bash
ADB="$HOME/android-sdk/platform-tools/adb"
"$ADB" pair PAIRING_IP:PAIRING_PORT PAIRING_CODE

# The values below are from one 2026-09-12 session and are illustrative only:
"$ADB" pair 192.168.86.144:39267 334333
```

Expected output: `Successfully paired to 192.168.86.144:39267 [guid=adb-52110DLAQ001UT-hkZkFs]`

The pairing port and code change every time the dialog is reopened, and the code expires in
~1-2 minutes — discover the port immediately before running `pair`.

#### Step 3: Connect to Device
```bash
# Connect using the main IP and port (not the pairing port)
"$ADB" connect DEVICE_IP:DEVICE_PORT
```

Expected output: `connected to DEVICE_IP:DEVICE_PORT`

**If that says `failed to connect` even though the address is right and its port accepts
TCP, the host is not paired** — go back to Step 2. On 2026-09-12 `connect` failed repeatedly
against an address that mdns advertised and that answered on its port; re-pairing fixed it
on the very next attempt. Don't hunt for a port typo first.

#### Step 4: Verify Connection
```bash
"$ADB" devices -l
```

Expected output should show your device:
```
List of devices attached
192.168.86.144:44457   device product:tokay model:Pixel_9 device:tokay transport_id:1
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

Three things that look like an absent phone and are not:

- `flutter devices` listing only Linux and Chrome — it can miss a transport
  `adb devices -l` sees, so check both.
- A failing `adb connect` while `adb devices -l` shows the phone online on the next line.
- `failed to connect` while mdns advertises the phone and its port accepts TCP: the host is
  not paired. Re-run Step 2 rather than suspecting the port.

**If `flutter devices` dies with `FileSystemException` on `~/.config/flutter` or
`~/.dart-tool`, that is a read-only `$HOME`, not a device problem** — the phone can be
perfectly connected while this fails. Under a sandbox that makes `$HOME` read-only, point
`HOME` at a writable copy and carry adb's key over; see the `run-app` skill's export block
for the exact recipe.

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

# Discover the live address - DHCP moves the phone, so never hardcode one here.
# (mdns is flaky: retry a couple of times before giving up.)
ADB="${ADB:-$HOME/android-sdk/platform-tools/adb}"
CONN="$("$ADB" mdns services | awk '/_adb-tls-connect/{print $NF}' | head -1)"
DEVICE_IP="${CONN%:*}"
DEVICE_PORT="${CONN##*:}"

if [ -z "$CONN" ]; then
    echo "No wireless device in mdns - retry, or open Wireless debugging on the phone."
    exit 1
fi

echo "Connecting to Android device wirelessly..."

# Kill any existing ADB server
"$ADB" kill-server

# Connect to device
"$ADB" connect "$DEVICE_IP:$DEVICE_PORT"

# Verify connection
if "$ADB" devices | grep -q "$DEVICE_IP:$DEVICE_PORT.*device"; then
    echo "✅ Successfully connected to $DEVICE_IP:$DEVICE_PORT"
    
    # Test connection
    DEVICE_MODEL=$("$ADB" -s $DEVICE_IP:$DEVICE_PORT shell getprop ro.product.model)
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
    echo "  - If the address is right and its port is open, this host is not paired - re-pair"
fi
```

### Pairing Helper Script
**File**: `pair-android-device.sh`
```bash
#!/bin/bash
# Helper script for pairing new Android devices

# Use the SDK adb, not the older one Debian installs at /usr/bin/adb
ADB="${ADB:-$HOME/android-sdk/platform-tools/adb}"

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

"$ADB" pair $PAIRING_IP:$PAIRING_PORT $PAIRING_CODE

if [ $? -eq 0 ]; then
    echo "✅ Pairing successful!"
    echo
    read -p "Now enter the main connection IP: " DEVICE_IP
    read -p "Connection port: " DEVICE_PORT
    
    echo "Connecting to device..."
    "$ADB" connect $DEVICE_IP:$DEVICE_PORT
    
    if [ $? -eq 0 ]; then
        echo "✅ Device connected successfully!"
        echo "📱 Device details:"
        "$ADB" -s $DEVICE_IP:$DEVICE_PORT shell getprop ro.product.model
        
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