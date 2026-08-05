package com.bytecats.metanoia

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.bytecats.metanoia.bible.DeepLink
import com.bytecats.metanoia.ui.screens.*
import com.bytecats.metanoia.ui.screens.settings.*
import com.bytecats.metanoia.ui.theme.MetanoiaTheme
import com.bytecats.metanoia.viewmodel.MainViewModel
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen

class MainActivity : ComponentActivity() {
    // Set from onCreate's initial intent and from onNewIntent (the activity
    // is launchMode="singleTask" — see AndroidManifest.xml — specifically so
    // a deep link tapped while the app is already running redelivers here
    // instead of spawning a second task). Held as Activity-level Compose
    // state (not a local var inside setContent) so a LaunchedEffect below can
    // react to it changing at any point in the activity's lifetime, not just
    // on first composition.
    private var pendingDeepLinkUri by mutableStateOf<Uri?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        pendingDeepLinkUri = intent?.data

        setContent {
            val viewModel: MainViewModel = viewModel()
            val navController = rememberNavController()

            // See com.bytecats.metanoia.bible.DeepLink / docs/ANDROID_DEEP_LINKS.md.
            // Consumed-once: cleared immediately after handling so backing out
            // of Bible and returning to the menu doesn't replay the same jump.
            LaunchedEffect(pendingDeepLinkUri) {
                val uri = pendingDeepLinkUri ?: return@LaunchedEffect
                DeepLink.parse(uri)?.let { ref ->
                    viewModel.pendingDeepLink = ref
                    navController.navigate("bible")
                }
                pendingDeepLinkUri = null
            }

            MetanoiaTheme {
                NavHost(navController = navController, startDestination = "menu") {
                    composable("menu") { MainMenu(navController, viewModel) }
                    composable("bible") { BibleScreen(viewModel) }
                    composable("collection") { CollectionScreen(navController, viewModel) }
                    composable("insights") {
                        InsightsRepositoryScreen(navController, viewModel) { viewModel.speak(it) }
                    }
                    composable("stats") {
                        LibraryStatsScreen(navController, viewModel.bibleManager)
                    }
                    composable("reading_stats") {
                        ReadingAnalyticsScreen(navController, viewModel)
                    }
                    composable("experimental_hub") {
                        ExperimentalHub(navController)
                    }
                    composable("voice_lab") {
                        VoiceLabScreen(navController, viewModel)
                    }
                    composable("data_management") {
                        DataManagementScreen(navController, viewModel)
                    }
                    composable("table_inspector/{tableName}") { backStack ->
                        val name = backStack.arguments?.getString("tableName") ?: "unknown"
                        TableInspectorScreen(navController, name, viewModel.bibleManager)
                    }
                    composable("settings_main") {
                        SettingsDashboard(navController)
                    }
                    composable("settings_gateway") {
                        GatewaySettingsPage(navController, viewModel.settingsManager)
                    }
                    composable("settings_audio") {
                        AudioSettingsPage(navController, viewModel.settingsManager)
                    }
                    composable("settings_reader") {
                        ReaderSettingsPage(navController, viewModel.settingsManager)
                    }
                    composable("settings_updates") {
                        UpdateSettingsPage(navController, viewModel)
                    }
                    composable("settings_changelog") {
                        com.bytecats.metanoia.ui.screens.settings.ChangelogScreen { navController.popBackStack() }
                    }
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        pendingDeepLinkUri = intent.data
    }
}
