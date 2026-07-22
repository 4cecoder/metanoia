package com.bytecats.metanoia

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.bytecats.metanoia.ui.screens.*
import com.bytecats.metanoia.ui.theme.MetanoiaTheme
import com.bytecats.metanoia.viewmodel.MainViewModel
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        setContent {
            val viewModel: MainViewModel = viewModel()
            val navController = rememberNavController()

            MetanoiaTheme {
                NavHost(navController = navController, startDestination = "menu") {
                    composable("menu") { MainMenu(navController, viewModel) }
                    composable("bible") { BibleScreen(navController, viewModel) }
                    composable("collection") { CollectionScreen(navController, viewModel) }
                    composable("insights") {
                        InsightsRepositoryScreen(navController, viewModel) { viewModel.speak(it) }
                    }
                    composable("stats") {
                        LibraryStatsScreen(navController, viewModel.bibleManager)
                    }
                    composable("experimental_hub") {
                        ExperimentalHub(navController)
                    }
                    composable("ai_lab") {
                        GraniteLabScreen(navController, viewModel.aiLogs, viewModel.llmManager!!)
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
                }
            }
        }
    }
}
