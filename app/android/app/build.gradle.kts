import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Real upload keystore + passwords live in key.properties, which is gitignored
// (see key.properties.example for the format). A fresh clone with no
// key.properties yet still builds — release just falls back to debug signing,
// the same "no secret, no crash" pattern as config/*.json and server/.env.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    namespace = "com.samarthkolur.budgetwise"
    compileSdk = flutter.compileSdkVersion

    // The NDK is genuinely required, and not by our own code — BudgetWise ships
    // none. path_provider_android depends on `jni`, which builds real native
    // sources (src/dartjni.c via CMake) and pins `ndkVersion flutter.ndkVersion`
    // in its own module. Removing this line does not avoid the requirement; it
    // only makes the app module disagree with the plugin about which NDK to use.
    //
    // A machine that has never accepted the Android SDK licences will fail here
    // with LicenceNotAcceptedException. Run `sdkmanager --licenses` once.
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // Permanent once published to Play. Changing it later means a new
        // listing, and re-registering the OAuth client that is keyed to it.
        applicationId = "com.samarthkolur.budgetwise"

        // Flutter's floor is 24 on 3.35, which already clears what
        // google_sign_in's Credential Manager path and Supabase need. Left as
        // flutter.minSdkVersion rather than pinned: `flutter build` rewrites
        // this file when it upgrades the template, and a hand-pinned value gets
        // silently reverted — which is worse than not pinning it, because the
        // comment then lies about what the build does.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Falls back to the debug cert only when key.properties is absent
            // (a fresh clone with no keystore yet). A debug-signed APK is what
            // got this build blocked by Play Protect on a second device, so
            // once key.properties exists this must resolve to "release", not
            // "debug" — confirm with `apksigner verify --print-certs` after a
            // build, don't just assume the gradle wiring took.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}
