plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "com.bytecats.metanoia"
    compileSdk = 35

    // Pinned debug keystore (mobile/debug.keystore, checked into git — not
    // sensitive, this is Android's own "debug" convention: fixed alias
    // "androiddebugkey", password "android"). Without this, AGP falls back
    // to ~/.android/debug.keystore, which is stable on one dev machine but
    // does NOT exist on GitHub Actions runners (fresh/ephemeral every run),
    // so every CI-built APK got signed with a different random key. Since
    // Android refuses to install an update whose signature doesn't match
    // the already-installed app (and uninstalling first wipes app-private
    // storage — the local bible.db cache, notes, highlights, favorites —
    // rendering the "rolling nightly release" pointless), every nightly
    // build must share this exact signing identity to actually update in
    // place instead of silently requiring a wipe-and-reinstall.
    signingConfigs {
        getByName("debug") {
            storeFile = file("../debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }

    defaultConfig {
        applicationId = "com.bytecats.metanoia"
        minSdk = 28
        targetSdk = 35
        // Was hardcoded to 1/"1.0" forever, so every nightly build looked
        // identical to Android and to a user checking Settings > App Info —
        // no way to tell which build is actually installed short of BuildConfig.
        // versionCode = total commit count: monotonically increasing across
        // this repo's history by construction, exactly what Android wants.
        versionCode = gitCommitCount()
        versionName = "1.0.${gitCommitCount()}-g${gitCommitSha().take(7)}"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        buildConfigField("String", "GIT_COMMIT_SHA", "\"${gitCommitSha()}\"")
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions {
        jvmTarget = "11"
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }

    testOptions {
        unitTests {
            // Some code paths under test (e.g. GatewayClient's catch-and-log
            // swallow) call android.util.Log, which is a stub that throws by
            // default under plain JUnit (no Robolectric). This makes Log.*
            // calls return default values instead of throwing, matching the
            // documented AGP recommendation for JVM unit tests.
            isReturnDefaultValues = true
        }
    }
}

fun gitCommitSha(): String = try {
    val process = ProcessBuilder("git", "rev-parse", "HEAD")
        .directory(rootDir)
        .redirectErrorStream(true)
        .start()
    val output = process.inputStream.bufferedReader().readText().trim()
    process.waitFor()
    if (output.matches(Regex("^[0-9a-f]{40}$"))) output else "unknown"
} catch (e: Exception) { "unknown" }

fun gitCommitCount(): Int = try {
    val process = ProcessBuilder("git", "rev-list", "--count", "HEAD")
        .directory(rootDir)
        .redirectErrorStream(true)
        .start()
    val output = process.inputStream.bufferedReader().readText().trim()
    process.waitFor()
    output.toIntOrNull() ?: 1
} catch (e: Exception) { 1 }

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.material.icons.extended)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.androidx.core.splashscreen)

    // --- CORE ENGINES ---
    implementation(libs.onnxruntime.mobile)

    // --- UTILS ---
    implementation(libs.okhttp)
    implementation(libs.jsoup)

    implementation(libs.androidx.compose.ui.text.google.fonts)

    testImplementation(libs.junit)
    testImplementation(libs.mockito.core)
    testImplementation(libs.mockito.kotlin)
    testImplementation(libs.org.json)
    androidTestImplementation(libs.androidx.test.ext.junit)
    androidTestImplementation(libs.androidx.test.espresso.core)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    debugImplementation(libs.androidx.compose.ui.tooling)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
}
dependencies {
    testImplementation("org.robolectric:robolectric:4.14.1")
    testImplementation(libs.androidx.compose.ui.test.junit4)
    testImplementation(libs.androidx.compose.ui.test.manifest)
}
