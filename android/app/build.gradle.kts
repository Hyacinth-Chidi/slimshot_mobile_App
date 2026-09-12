import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.techfamz.slimshotai"
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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.techfamz.slimshotai"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24

        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Media3 modules must all be on the same version.
    val media3Version = "1.11.0"

    // Playback: the two preview lanes.
    implementation("androidx.media3:media3-exoplayer:$media3Version")
    implementation("androidx.media3:media3-common:$media3Version")

    // Export output. The standalone muxer, without Transformer — Transformer's
    // composition model cannot express a two-texture shader blend, so it cannot
    // be the export engine (docs/dead-ends.md entry 3), but its muxer is worth
    // having on its own: B-frames, edit lists, and Google's device quirk
    // handling instead of the platform MediaMuxer's.
    implementation("androidx.media3:media3-muxer:$media3Version")

    // Deliberately absent: media3-ui (the preview is a Flutter texture, not a
    // PlayerView), media3-effect and media3-transformer (nothing references
    // them now that the Transformer export route is ruled out).

    // Local JVM unit tests. These run on the host, not a device, so they can
    // only cover pure arithmetic — which is exactly what they are here for:
    // the text animation curves exist twice, once in Dart for the preview and
    // once in Kotlin for the export, and a shared fixture asserts the two
    // produce identical values. Nothing that touches the Android framework
    // belongs in this source set.
    testImplementation("junit:junit:4.13.2")

    // Deliberately *not* here: `org.json:json`. The framework's
    // `android.util.JSONObject` is stubbed to throw "not mocked" in local unit
    // tests, so the obvious fix is the real org.json artifact — but that is one
    // more thing to download, and the fixture is a flat, generated file with a
    // known shape. The test parses it with a few lines of its own instead
    // (`FixtureJson` in TextAnimationCurvesTest), so the only unit-test
    // dependency is JUnit and the suite runs with no network at all.
    // `testOptions { unitTests.isReturnDefaultValues = true }` is also avoided:
    // it would silence every other framework stub as well, turning a missing
    // call into a silently wrong value rather than a loud failure.
}
