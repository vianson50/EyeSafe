import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.eyesafe"
    // flutter_webrtc (androidx.fragment 1.7) exige compileSdk >= 34.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // Identifiant de production — requis pour le Play Store.
        applicationId = "ci.eyesafe.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Signature RELEASE avec le keystore de production — la clé de debug
    // n'est plus utilisée. Le keystore vit hors du projet (~/eyesafe-release.keystore),
    // les secrets dans android/key.properties (gitignoré).
    val keystoreProperties = Properties().apply {
        val f = rootProject.file("key.properties")
        if (f.exists()) load(FileInputStream(f))
    }
    val hasReleaseKeystore = keystoreProperties["storeFile"] != null

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String?
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                // Repli debug UNIQUEMENT en local sans keystore (jamais en prod).
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

flutter {
    source = "../.."
}

// Firebase : appliqué uniquement si google-services.json est présent
// (téléchargé depuis la console Firebase → android/app/google-services.json).
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}
