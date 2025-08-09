# Free Flight Log

A cross-platform mobile application for logging paraglider, hang glider, and microlight flights. Built with Flutter, featuring local SQLite database storage, comprehensive flight tracking, and multi-platform support.

## Features

- **Flight Logging**: Manual flight entry with date, time, duration, altitude, and notes
- **Local Database**: SQLite storage with no cloud dependencies
- **Cross-Platform**: Runs on Linux, Android, iOS, macOS, and Windows
- **Flight Statistics**: Track total flights, hours, and personal records
- **Form Validation**: Comprehensive input validation and error handling
- **Material Design**: Modern UI following Material Design 3 principles

## Prerequisites

Before setting up the development environment, ensure your system meets these requirements:

- **Operating System**: Linux (Ubuntu/Debian), macOS, or Windows
- **Storage**: At least 2GB free space for Flutter SDK and tools
- **Memory**: 4GB RAM minimum (8GB recommended)
- **Network**: Internet connection for downloading dependencies

## Development Environment Setup

### 1. Install Flutter SDK

#### Linux/macOS
```bash
# Download Flutter SDK
git clone https://github.com/flutter/flutter.git -b stable
cd flutter

# Add Flutter to PATH (choose one method)
# Option A: Temporary (current session only)
export PATH="$PATH:`pwd`/bin"

# Option B: Permanent (recommended)
echo 'export PATH="$PATH:$HOME/flutter/bin"' >> ~/.bashrc
source ~/.bashrc

# Verify installation
flutter doctor
```

#### Windows
```powershell
# Download Flutter SDK manually from https://flutter.dev/docs/get-started/install/windows
# Extract to C:\flutter
# Add C:\flutter\bin to your PATH in System Environment Variables

# Verify installation
flutter doctor
```

### 2. Platform-Specific Development Tools

#### Linux Desktop Development
```bash
# Update package list
sudo apt update

# Install build tools
sudo apt install -y cmake ninja-build pkg-config

# Install GTK development libraries for Linux desktop apps
sudo apt install -y libgtk-3-dev libblkid-dev

# Install additional development tools
sudo apt install -y clang gcc g++

# Install Git (if not already installed)
sudo apt install -y git curl wget

# Verify installation
cmake --version
ninja --version
```

#### Android Development

##### Install Android Studio
```bash
# Download Android Studio from https://developer.android.com/studio
# Or install via snap (Ubuntu)
sudo snap install android-studio --classic

# Alternative: Install Android command line tools only
sudo apt install -y android-tools-adb android-tools-fastboot
```

##### Set up Android SDK
```bash
# Set environment variables (add to ~/.bashrc for persistence)
export ANDROID_HOME=$HOME/Android/Sdk
export PATH=$PATH:$ANDROID_HOME/tools:$ANDROID_HOME/platform-tools
export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin

# Reload environment
source ~/.bashrc

# Accept Android licenses
flutter doctor --android-licenses
```

##### Enable USB Debugging on Android Device
1. Go to **Settings** → **About Phone**
2. Tap **Build Number** 7 times to enable Developer Options
3. Go to **Settings** → **Developer Options**
4. Enable **USB Debugging**
5. Connect device via USB and allow debugging when prompted

#### iOS Development (macOS only)
```bash
# Install Xcode from Mac App Store
# Install Xcode command line tools
xcode-select --install

# Install CocoaPods
sudo gem install cocoapods

# Accept Xcode license
sudo xcodebuild -license accept
```

#### Windows Development
```powershell
# Install Visual Studio 2022 with C++ development tools
# Download from https://visualstudio.microsoft.com/

# Required workloads:
# - Desktop development with C++
# - Game development with C++ (for CMake tools)
```

### 3. Verify Flutter Installation

Run Flutter doctor to check your setup:

```bash
flutter doctor
```

Expected output should show:
- ✅ Flutter (Channel stable, 3.32.8+)
- ✅ Linux toolchain (for Linux development)
- ✅ Android toolchain (if Android Studio is installed)
- ✅ Connected device (when device is connected)

### 4. Project Setup

#### Clone and Setup Project
```bash
# Clone the repository
git clone <your-repository-url>
cd free_flight_log_app

# Install Flutter dependencies
flutter pub get

# Verify project setup
flutter analyze
```

#### Check Available Devices
```bash
# List connected devices
flutter devices

# Expected output examples:
# Linux (desktop) • linux • linux-x64
# Android device • device-id • android-arm64
```

### 5. Build and Run Commands

#### Development (Debug Mode)
```bash
# Run on Linux desktop
flutter run -d linux

# Run on connected Android device
flutter run -d android

# Run with hot reload enabled
flutter run --hot
```

#### Production Builds
```bash
# Build Linux desktop application
flutter build linux

# Build Android APK (debug)
flutter build apk --debug

# Build Android APK (release)
flutter build apk --release

# Build Android App Bundle for Play Store
flutter build appbundle --release
```

#### Install on Device
```bash
# Install debug APK on connected Android device
flutter install

# Install specific APK file
adb install build/app/outputs/flutter-apk/app-release.apk
```

### 6. Key Dependencies

This project uses these main dependencies:

```yaml
dependencies:
  flutter: sdk
  sqflite: ^2.3.0                    # SQLite database
  sqflite_common_ffi: ^2.3.0         # SQLite for desktop platforms
  shared_preferences: ^2.2.0         # Settings storage
  provider: ^6.1.0                   # State management
  google_maps_flutter: ^2.5.0        # Map visualization
  file_picker: ^6.0.0                # IGC file import
  fl_chart: ^0.65.0                  # Charts for altitude/climb rate
  intl: ^0.18.0                      # Date/time formatting
```

### 7. Project Architecture

- **Pattern**: MVVM with Repository pattern
- **Database**: SQLite via sqflite (mobile) and sqflite_common_ffi (desktop)
- **State Management**: Provider
- **UI Framework**: Flutter with Material Design 3

```
lib/
├── data/
│   ├── models/           # Flight, Site, Wing data models
│   ├── repositories/     # Data access layer
│   └── datasources/      # Database helper
├── presentation/
│   ├── screens/          # UI screens
│   ├── widgets/          # Reusable components
│   └── providers/        # State management
└── services/             # Business logic services
```

## Troubleshooting

### Common Issues and Solutions

#### 1. "Database factory not initialized" Error
```bash
# Ensure sqflite_common_ffi is properly installed
flutter pub get
flutter clean
flutter build linux
```

#### 2. Android Device Not Detected
```bash
# Check USB debugging is enabled
adb devices

# Restart ADB server if needed
adb kill-server
adb start-server

# Check device permissions
flutter devices
```

#### 3. Linux Build Issues
```bash
# Install missing libraries
sudo apt install -y libgtk-3-dev libblkid-dev

# Update CMake if needed
sudo apt install -y cmake ninja-build

# Clear build cache
flutter clean
flutter pub get
```

#### 4. File Picker Warnings (Safe to Ignore)
The app shows warnings about file_picker plugin implementations. These are informational only and don't affect functionality.

#### 5. Flutter Doctor Issues
```bash
# Update Flutter to latest stable
flutter upgrade

# Check for specific issues
flutter doctor -v

# Accept Android licenses
flutter doctor --android-licenses
```

### Performance Tips

- Use `flutter run --release` for better performance testing
- Enable USB 3.0 for faster device deployment
- Use `flutter build` commands for final testing
- Monitor app performance with `flutter run --profile`

## Development Workflow

1. **Setup**: Follow installation steps above
2. **Development**: Use `flutter run -d linux` for rapid iteration
3. **Testing**: Test on multiple platforms before release
4. **Building**: Use release builds for distribution

## Contributing

1. Follow Flutter/Dart style guidelines
2. Use the established MVVM + Repository pattern
3. Add tests for new features
4. Update this README for any new setup requirements

## Support

- Flutter Documentation: https://docs.flutter.dev/
- Flutter Community: https://flutter.dev/community
- Project Issues: Create an issue in this repository

---

**System Requirements Met**: ✅ Flutter 3.32.8, Dart 3.8.1, CMake 3.25.1, Ninja 1.11.1