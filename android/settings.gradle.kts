pluginManagement {
    val flutterSdkPath =
        run {
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
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
    id("com.google.gms.google-services") version "4.4.2" apply false
}

// flutter_webrtc publie encore compileSdk 31 alors qu'androidx.fragment 1.7
// (dépendance transitive) exige 34+ : on force le niveau AVANT l'évaluation
// de chaque sous-projet Android (pattern gradle.beforeProject).
gradle.beforeProject {
    if (name != "app") {
        afterEvaluate {
            extensions.findByName("android")?.let { ext ->
                when (ext) {
                    is com.android.build.gradle.LibraryExtension -> ext.compileSdk = 36
                    is com.android.build.gradle.BaseExtension -> ext.compileSdkVersion(36)
                }
            }
        }
    }
}

include(":app")
