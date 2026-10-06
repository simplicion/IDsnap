import java.util.Properties
import java.io.FileInputStream
import groovy.json.JsonSlurper
import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: CI writes android/key.properties from secrets. Without it,
// local release builds fall back to debug signing so they can be tested on a
// device — never publish those. On CI (CI=true) a missing key.properties is a
// hard error, so an unsigned build can't reach a release.
//
// Release commands (see README "Release builds"):
//   flutter build appbundle --release                    # Google Play
//   flutter build apk --release --split-per-abi \
//     --target-platform android-arm,android-arm64        # direct downloads
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
} else if (System.getenv("CI") == "true" &&
    gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }
) {
    throw GradleException(
        "android/key.properties is missing: refusing to build a debug-signed release on CI.",
    )
}

// Monetization (ADR-0013). Flutter hands the dart-defines to Gradle as
// base64 entries in the "dart-defines" property.
//
//   IDSNAP_MONETIZATION=ads (default)  free with ads; needs AdMob IDs
//   IDSNAP_MONETIZATION=licence        180 Pay licence server (ADR-0012);
//                                      needs IDSNAP_LICENSE_URL (https) and
//                                      IDSNAP_LICENSE_PUBLIC_KEY; no ads
//   IDSNAP_MONETIZATION=store          Play Billing; no ads
//
// AdMob IDs live in ONE committed file, assets/config/admob.json, which
// the app also reads as a bundled asset. Gradle needs the App ID for the
// manifest (com.google.android.gms.ads.APPLICATION_ID): without a
// well-formed one the ads SDK crashes the app at launch.
//   - release: the real App ID from the file (or
//     --dart-define=IDSNAP_ADMOB_APP_ID_ANDROID). A release that shows ads
//     FAILS here if the App ID or an ad unit is missing, malformed or one of
//     Google's sample IDs (they earn nothing).
//   - debug / profile: ALWAYS Google's sample App ID (tapping your own live
//     ads can get the AdMob account suspended), unless the build names
//     registered test phones with IDSNAP_ADMOB_TEST_DEVICE_IDS.
val isReleaseBuild = gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }
val dartDefines: Map<String, String> = (project.findProperty("dart-defines") as String?)
    .orEmpty()
    .split(",")
    .filter { it.isNotBlank() }
    .map { String(Base64.getDecoder().decode(it)) }
    .associate { it.substringBefore("=") to it.substringAfter("=", "") }

val monetization = (dartDefines["IDSNAP_MONETIZATION"] ?: "ads").trim().lowercase()
    .let { if (it == "license") "licence" else it }
if (monetization !in setOf("ads", "licence", "store")) {
    throw GradleException(
        "IDSNAP_MONETIZATION must be ads, licence or store (got \"$monetization\").",
    )
}
val adsDisabled = dartDefines["IDSNAP_ADS_DISABLED"] == "true"
val buildShowsAds = monetization == "ads" && !adsDisabled

val googleSamplePublisher = "ca-app-pub-3940256099942544"
val googleSampleAppId = "$googleSamplePublisher~3347511713"

@Suppress("UNCHECKED_CAST")
val admobAndroid: Map<String, String> = run {
    val file = rootProject.file("../assets/config/admob.json")
    if (!file.exists()) throw GradleException("Missing ${file.path} (AdMob IDs, ADR-0013).")
    val json = JsonSlurper().parse(file) as Map<String, Any?>
    val android = (json["android"] as? Map<String, Any?>).orEmpty()
    fun pick(key: String, define: String) =
        dartDefines[define]?.trim().takeUnless { it.isNullOrEmpty() }
            ?: (android[key] as? String).orEmpty().trim()
    mapOf(
        "the App ID" to pick("appId", "IDSNAP_ADMOB_APP_ID_ANDROID"),
        "the banner unit" to pick("banner", "IDSNAP_ADMOB_BANNER_ID"),
        "the interstitial unit" to pick("interstitial", "IDSNAP_ADMOB_INTERSTITIAL_ID"),
        "the native unit" to pick("native", "IDSNAP_ADMOB_NATIVE_ID"),
    )
}
val admobProblems: List<String> = admobAndroid.mapNotNull { (name, value) ->
    val pattern = if (name == "the App ID") {
        Regex("^ca-app-pub-\\d{16}~\\d{10}$")
    } else {
        Regex("^ca-app-pub-\\d{16}/\\d{10}$")
    }
    when {
        value.isEmpty() -> "$name is missing"
        !pattern.matches(value) -> "$name is not an AdMob ID"
        value.startsWith(googleSamplePublisher) -> "$name is one of Google's TEST IDs (they earn nothing)"
        else -> null
    }
}
val realAdmobAppId = admobAndroid.getValue("the App ID")
// Debug/profile opt-in to the real units, on registered test phones only.
val realAdsOnTestDevices = !dartDefines["IDSNAP_ADMOB_TEST_DEVICE_IDS"].isNullOrBlank()

if (isReleaseBuild) {
    if (buildShowsAds && admobProblems.isNotEmpty()) {
        throw GradleException(
            "This release build shows ads (IDSNAP_MONETIZATION=ads) but its AdMob IDs are not " +
                "usable: ${admobProblems.joinToString("; ")}. Fix " +
                "apps/scanner/assets/config/admob.json or the IDSNAP_ADMOB_* dart-defines " +
                "(README > Release builds), or build with --dart-define=IDSNAP_ADS_DISABLED=true " +
                "for a build without ads.",
        )
    }
    // Licence settings (ADR-0012), licence mode only: without them the app
    // throws LicenceConfigError at startup. Hard error on CI, warning
    // locally (so a local build can still be inspected).
    if (monetization == "licence") {
        val problems = buildList {
            if (dartDefines["IDSNAP_LICENSE_URL"]?.startsWith("https://") != true) {
                add("IDSNAP_LICENSE_URL (https)")
            }
            if (dartDefines["IDSNAP_LICENSE_PUBLIC_KEY"].isNullOrBlank()) {
                add("IDSNAP_LICENSE_PUBLIC_KEY")
            }
        }
        if (problems.isNotEmpty()) {
            val message = "Licence-mode release build without --dart-define " +
                "${problems.joinToString()}: the app will refuse to start " +
                "(see README > Release builds)."
            if (System.getenv("CI") == "true") throw GradleException(message)
            logger.warn("WARNING: $message")
        }
    }
}

// The manifest must always carry a well-formed App ID, also in builds that
// never start the ads SDK (paid modes, IDSNAP_ADS_DISABLED).
val releaseAdmobAppId =
    if (Regex("^ca-app-pub-\\d{16}~\\d{10}$").matches(realAdmobAppId)) realAdmobAppId else googleSampleAppId
val debugAdmobAppId = if (realAdsOnTestDevices) releaseAdmobAppId else googleSampleAppId

android {
    namespace = "com.docscan.docscan_scanner"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.idsnap.app"
        // Android 7.0+ (Flutter's own minimum; ML Kit, camera, local_auth and
        // SQLCipher all support it).
        minSdk = 24
        // Follow the Flutter SDK (36 with Flutter 3.47). Google Play raises the
        // required target API every year (31 Aug) — confirm in Play Console >
        // Policy status before each upload.
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                enableV1Signing = true
                enableV2Signing = true
            }
        }
    }

    buildTypes {
        debug {
            manifestPlaceholders["admobAppId"] = debugAdmobAppId
        }
        getByName("profile") {
            manifestPlaceholders["admobAppId"] = debugAdmobAppId
        }
        release {
            manifestPlaceholders["admobAppId"] = releaseAdmobAppId
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
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

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Bundled (offline) OCR model for Hindi/Marathi/Nepali. Latin ships with
    // the plugin. Bundled models add size but never download at runtime.
    implementation("com.google.mlkit:text-recognition-devanagari:16.0.1")
}
