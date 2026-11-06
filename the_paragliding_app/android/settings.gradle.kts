pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // AGP 9 is blocked by flutter_inappwebview_android 1.1.3, which still uses
    // the removed proguard-android.txt. Flutter 3.47 warns that AGP 8 support
    // will be dropped, so move to 9.1.0 once that plugin ships a fix. Then
    // receive_sharing_intent can go back to 1.9.x (it needs compileSdk 37).
    id("com.android.application") version "8.13.2" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")
