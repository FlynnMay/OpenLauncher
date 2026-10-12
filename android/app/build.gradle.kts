import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The release key, kept out of git: android/key.properties (storeFile,
// storePassword, keyAlias, keyPassword). Without it, the debug key signs.
val keyFile = rootProject.file("key.properties")
val key = Properties().apply { if (keyFile.exists()) keyFile.inputStream().use(::load) }

/** 0.1.0 -> 100. An update must have a higher code than what it replaces. */
fun versionCodeOf(name: String): Int {
    val (major, minor, patch) = name.split(".").map(String::toInt)
    return major * 10000 + minor * 100 + patch
}

android {
    namespace = "com.maypoint.openlauncher"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.maypoint.openlauncher"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // The embedded ADB client (dadb) needs java.util.Base64, added in API 26.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Both from the version in pubspec.yaml.
        versionCode = versionCodeOf(flutter.versionName)
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keyFile.exists()) {
            create("release") {
                storeFile = file(key.getProperty("storeFile"))
                storePassword = key.getProperty("storePassword")
                keyAlias = key.getProperty("keyAlias")
                keyPassword = key.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        // Debug builds too, so that one installs over a release.
        val signing = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        release { signingConfig = signing }
        debug { signingConfig = signing }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Required by the Pigeon-generated bridge (suspend functions).
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    // ADB client used by the one-press setup to talk to the TV's own adbd.
    implementation("dev.mobile:dadb:2.0.0")
}
