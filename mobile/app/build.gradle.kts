plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
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
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7") // REQUIRED
    implementation("androidx.activity:activity-compose:1.10.0")
    implementation(platform("androidx.compose:compose-bom:2025.02.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.navigation:navigation-compose:2.8.7")
    implementation("androidx.core:core-splashscreen:1.0.1")
    
    // --- CORE ENGINES ---
    implementation("com.microsoft.onnxruntime:onnxruntime-mobile:1.18.0")
    implementation("com.google.mediapipe:tasks-genai:0.10.14")
    
    // --- UTILS ---
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.jsoup:jsoup:1.17.2")
    
    implementation("androidx.compose.ui:ui-text-google-fonts:1.7.8")
    
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.mockito:mockito-core:5.11.0")
    testImplementation("org.mockito.kotlin:mockito-kotlin:5.2.1")
    testImplementation("org.json:json:20240303")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.6.1")
    androidTestImplementation(platform("androidx.compose:compose-bom:2025.02.00"))
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}
