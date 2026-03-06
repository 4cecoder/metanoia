package com.bytecats.metanoia.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import com.bytecats.metanoia.ui.components.ModuleCard
import com.bytecats.metanoia.viewmodel.MainViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainMenu(navController: NavController, viewModel: MainViewModel) {
    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                title = { 
                    Text(
                        "METANOIA", 
                        style = MaterialTheme.typography.displayLarge,
                        letterSpacing = 6.sp,
                        color = MaterialTheme.colorScheme.primary
                    ) 
                },
                actions = {
                    IconButton({ navController.navigate("settings_main") }) {
                        Icon(Icons.Default.Settings, null)
                    }
                }
            )
        }
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .padding(innerPadding)
                .fillMaxSize()
                .padding(24.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(24.dp)
        ) {
            // HIGH-FIDELITY CORE MODULE GRID
            Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    ModuleCard("BIBLE", "Reader", Icons.AutoMirrored.Filled.MenuBook, Color(0xFF9ece6a), Modifier.weight(1f)) {
                        navController.navigate("bible")
                    }
                    ModuleCard("COLLECTION", "Scholarship", Icons.Default.CollectionsBookmark, Color(0xFFbb9af7), Modifier.weight(1f)) {
                        navController.navigate("collection")
                    }
                }
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    ModuleCard("DATA", "Management", Icons.Default.Storage, Color(0xFFf7768e), Modifier.weight(1f)) {
                        navController.navigate("data_management")
                    }
                    ModuleCard("LABS", "Research", Icons.Default.Science, Color(0xFFff9e6a), Modifier.weight(1f)) {
                        navController.navigate("experimental_hub")
                    }
                }
            }
        }
    }
}
