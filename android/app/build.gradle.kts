import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties()
if (keyPropertiesFile.exists()) {
    keyProperties.load(FileInputStream(keyPropertiesFile))
}

android {
    namespace = "com.mazino2d.simsplit"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.mazino2d.simsplit"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keyPropertiesFile.exists()) {
            create("release") {
                keyAlias = keyProperties["keyAlias"] as String
                keyPassword = keyProperties["keyPassword"] as String
                storeFile = keyProperties["storeFile"]?.let { file(it as String) }
                storePassword = keyProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Never fall back to the debug key: a debug-signed AAB cannot be
            // uploaded to Play. A missing key.properties fails release tasks
            // (see the taskGraph check below).
            if (keyPropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
            // R8 code + resource shrinking. Flutter's default keep rules cover
            // the engine and plugins; add proguard-rules.pro only if a release
            // build shows missing-class issues.
            isMinifyEnabled = true
            isShrinkResources = true
        }
    }
}

// Fail fast, only when a release variant is actually being built, instead of
// producing an unsigned or debug-signed artifact. Debug builds and
// `flutter run` are unaffected.
gradle.taskGraph.whenReady {
    val buildsRelease = allTasks.any { it.project == project && it.name.contains("Release") }
    if (buildsRelease && !keyPropertiesFile.exists()) {
        throw GradleException(
            "Release signing is not configured: ${keyPropertiesFile.path} is missing. " +
                "Copy android/key.properties.example to android/key.properties and fill in " +
                "your upload keystore details (see README > Releasing).",
        )
    }
}

flutter {
    source = "../.."
}
