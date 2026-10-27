import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()

if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.example.voltbuddy"
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
        applicationId = "com.example.voltbuddy"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    // Two builds from one codebase:
    //  study - the research build sideloaded to participants. Must keep the
    //          Phase 1 app ID and debug key so it updates their installed app.
    //  play  - the Google Play build: its own app ID, signed with the upload
    //          key from android/key.properties (not in git).
    flavorDimensions += "distribution"
    productFlavors {
        create("study") {
            dimension = "distribution"
            applicationId = "com.example.voltbuddy"
            signingConfig = signingConfigs.getByName("debug")
            resValue("bool", "study_events_enabled", "true")
        }
        create("play") {
            dimension = "distribution"
            applicationId = "com.voltbuddy.app"
            // No research event log in the public app (see StudyEvents).
            resValue("bool", "study_events_enabled", "false")
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

dependencies {
    implementation("androidx.work:work-runtime-ktx:2.9.1")
}

flutter {
    source = "../.."
}