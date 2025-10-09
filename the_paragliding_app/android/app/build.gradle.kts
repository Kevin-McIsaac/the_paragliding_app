plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.io.ByteArrayOutputStream
import java.io.FileInputStream
import java.util.Properties

// Function to get git commit hash
fun getGitCommitHash(): String {
    return try {
        val stdout = ByteArrayOutputStream()
        exec {
            commandLine("git", "rev-parse", "--short", "HEAD")
            standardOutput = stdout
        }
        stdout.toString().trim()
    } catch (e: Exception) {
        "unknown"
    }
}

// Function to get git branch name
fun getGitBranchName(): String {
    return try {
        val stdout = ByteArrayOutputStream()
        exec {
            commandLine("git", "rev-parse", "--abbrev-ref", "HEAD")
            standardOutput = stdout
        }
        stdout.toString().trim()
    } catch (e: Exception) {
        "main"
    }
}

// Load keystore properties from file
fun getKeystoreProperties(): Properties? {
    val keystorePropertiesFile = rootProject.file("key.properties")
    return if (keystorePropertiesFile.exists()) {
        val keystoreProperties = Properties()
        keystoreProperties.load(FileInputStream(keystorePropertiesFile))
        keystoreProperties
    } else {
        null
    }
}

android {
    namespace = "com.theparaglidingapp"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    buildFeatures {
        buildConfig = true
    }

    // Signing configurations
    signingConfigs {
        val keystoreProperties = getKeystoreProperties()
        if (keystoreProperties != null) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.theparaglidingapp"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        // Pass git commit hash and branch to Flutter
        buildConfigField("String", "GIT_COMMIT", "\"${getGitCommitHash()}\"")
        buildConfigField("String", "GIT_BRANCH", "\"${getGitBranchName()}\"")
    }

    buildTypes {
        debug {
            // Speed up debug builds
            isMinifyEnabled = false
            isShrinkResources = false
            isCrunchPngs = false
        }
        release {
            // Use release signing config if available, otherwise fall back to debug
            val keystoreProperties = getKeystoreProperties()
            signingConfig = if (keystoreProperties != null) {
                signingConfigs.getByName("release")
            } else {
                // Fallback to debug for development (not for production!)
                println("WARNING: No key.properties found. Using debug signing. DO NOT use for production release!")
                signingConfigs.getByName("debug")
            }

            // Enable minification and resource shrinking for smaller APK
            isMinifyEnabled = true
            isShrinkResources = true

            // Use ProGuard rules
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}
