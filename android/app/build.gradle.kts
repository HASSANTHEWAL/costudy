plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

/**
 * Host that serves Firebase Authentication email sign-in links, read straight
 * out of google-services.json.
 *
 * Firebase Dynamic Links shut down on 25 August 2025. Email link sign-in now
 * routes through the project's Firebase Hosting default domain
 * (PROJECT_ID.firebaseapp.com), and the app claims those links with an
 * App Links intent filter in AndroidManifest.xml. That filter needs the host
 * as a literal string, so it is derived here and injected as a manifest
 * placeholder rather than hardcoded — hardcoding it would silently break the
 * sign-in loop the moment the project ID changes.
 */
val firebaseAuthHost: String = run {
    val configFile = file("google-services.json")
    require(configFile.exists()) {
        "android/app/google-services.json is missing. Download it from the Firebase " +
            "console (Project settings > Your apps > Android) and place it there."
    }
    @Suppress("UNCHECKED_CAST")
    val config = groovy.json.JsonSlurper().parse(configFile) as Map<String, Any>
    @Suppress("UNCHECKED_CAST")
    val projectInfo = config["project_info"] as Map<String, Any>
    "${projectInfo["project_id"]}.firebaseapp.com"
}

android {
    namespace = "com.example.costudy"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        // Must match the package_name registered in google-services.json.
        applicationId = "com.example.costudy"
        // Android 8.0, per proposal D.3. Also clears Firebase Auth's floor of 23.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        manifestPlaceholders["firebaseAuthHost"] = firebaseAuthHost
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
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
