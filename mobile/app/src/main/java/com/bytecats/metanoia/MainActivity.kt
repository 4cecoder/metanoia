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
import kotlinx.coroutines.launch
import kotlinx.coroutines.MainScope

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
                    composable("bible") { BibleScreen(viewModel) }
                    composable("collection") { CollectionScreen(viewModel) }
                    composable("insights") {
                        InsightsRepositoryScreen(viewModel) { viewModel.speak(it) }
                    }
                    composable("stats") {
                        LibraryStatsScreen(viewModel.bibleManager)
                    }
                    composable("experimental_hub") { 
                        ExperimentalHub(navController) 
                    }
                    composable("ai_lab") { 
                        GraniteLabScreen(viewModel.aiLogs, viewModel.llmManager!!) 
                    }
                    composable("voice_lab") { 
                        VoiceLabScreen(viewModel) 
                    }
                    composable("data_management") { 
                        DataManagementScreen(navController, viewModel) 
                    }
                    composable("table_inspector/{tableName}") { backStack -> 
                        val name = backStack.arguments?.getString("tableName") ?: "unknown"
                        TableInspectorScreen(name, viewModel.bibleManager)
                    }
                    composable("settings_main") { 
                        SettingsDashboard(navController) 
                    }
                    composable("settings_audio") { 
                        AudioSettingsPage(viewModel.settingsManager) 
                    }
                    composable("settings_reader") { 
                        ReaderSettingsPage(viewModel.settingsManager) 
                    }
                }
            }
        }
    }
}
