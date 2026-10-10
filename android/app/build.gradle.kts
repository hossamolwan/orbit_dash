import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigningPropertiesFile = rootProject.file("key.properties")
val releaseSigningProperties = Properties()
if (releaseSigningPropertiesFile.isFile) {
    releaseSigningPropertiesFile.inputStream().use { input ->
        releaseSigningProperties.load(input)
    }
}

val userProfilePath = System.getenv("USERPROFILE")
val releaseStoreFile = releaseSigningProperties.getProperty("storeFile")
    ?.replace("%USERPROFILE%", userProfilePath ?: "%USERPROFILE%")
    ?.takeIf { it.isNotBlank() && !it.contains("REPLACE_WITH") }
    ?.let { file(it) }
val releaseSigningConfigured = listOf(
    "storeFile",
    "storePassword",
    "keyAlias",
    "keyPassword",
).all { key ->
    releaseSigningProperties.getProperty(key)
        ?.let { it.isNotBlank() && !it.contains("REPLACE_WITH") } == true
} && releaseStoreFile?.isFile == true

val releaseSigningError =
    "Release signing is not configured. Set a valid keystore path, alias, " +
        "store password, and key password in android/key.properties."

tasks.configureEach {
    if (
        name == "packageRelease" ||
        name == "bundleRelease" ||
        name == "assembleRelease"
    ) {
        doFirst {
            if (!releaseSigningConfigured) {
                throw GradleException(releaseSigningError)
            }
        }
    }
}

android {
    namespace = "com.example.orbit_dash"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.orbit_dash"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningConfigured) {
            create("release") {
                storeFile = checkNotNull(releaseStoreFile)
                storePassword = releaseSigningProperties.getProperty("storePassword")
                keyAlias = releaseSigningProperties.getProperty("keyAlias")
                keyPassword = releaseSigningProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (releaseSigningConfigured) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                signingConfig = null
            }
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
