plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
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

    buildTypes {
        release {
            // Debug keys, so `flutter run --release` works locally.
            //
            // Release signing is Phase 8 and is deliberately NOT configured
            // here: the upload keystore must not live in this repository, and
            // its SHA-1 has to be registered on the Google Android OAuth client
            // or sign-in works in debug and fails in production.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
