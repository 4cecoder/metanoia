package com.bytecats.metanoia.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import com.bytecats.metanoia.ui.components.ModuleCard
import com.bytecats.metanoia.viewmodel.MainViewModel
import com.bytecats.metanoia.ui.effects.cyberpunkHudBackground
import com.bytecats.metanoia.ui.effects.cyberpunkGlowAura
import androidx.compose.animation.core.withInfiniteAnimationFrameMillis
import androidx.compose.runtime.produceState
import androidx.compose.runtime.getValue

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainMenu(navController: NavController, viewModel: MainViewModel) {
    val time by produceState(initialValue = 0f) {
        while (true) {
            withInfiniteAnimationFrameMillis {
                value = it / 1000f
            }
        }
    }

    Scaffold(
        modifier = Modifier.cyberpunkHudBackground(time),
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
            viewModel.availableUpdate.value?.let { update ->
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.secondaryContainer)
                ) {
                    Row(
                        modifier = Modifier.padding(start = 16.dp, end = 4.dp, top = 4.dp, bottom = 4.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text("A newer nightly build is available", fontWeight = FontWeight.Bold, style = MaterialTheme.typography.bodyMedium)
                            Text(
                                "Build ${update.commitSha?.take(7) ?: "unknown"}",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.outline
                            )
                        }
                        TextButton(onClick = { navController.navigate("settings_updates") }) { Text("View") }
                        IconButton(onClick = { viewModel.dismissAvailableUpdate() }) {
                            Icon(Icons.Default.Close, contentDescription = "Dismiss")
                        }
                    }
                }
            }

            // HIGH-FIDELITY CORE MODULE GRID
            Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    ModuleCard("BIBLE", "Reader", Icons.AutoMirrored.Filled.MenuBook, Color(0xFF9ece6a), Modifier.weight(1f).cyberpunkGlowAura(time, Color(0xFF9ece6a).copy(alpha = 0.3f))) {
                        navController.navigate("bible")
                    }
                    ModuleCard("COLLECTION", "Scholarship", Icons.Default.CollectionsBookmark, Color(0xFFbb9af7), Modifier.weight(1f).cyberpunkGlowAura(time, Color(0xFFbb9af7).copy(alpha = 0.3f))) {
                        navController.navigate("collection")
                    }
                }
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    ModuleCard("DATA", "Management", Icons.Default.Storage, Color(0xFFf7768e), Modifier.weight(1f).cyberpunkGlowAura(time, Color(0xFFf7768e).copy(alpha = 0.3f))) {
                        navController.navigate("data_management")
                    }
                    ModuleCard("LABS", "Research", Icons.Default.Science, Color(0xFFff9e6a), Modifier.weight(1f).cyberpunkGlowAura(time, Color(0xFFff9e6a).copy(alpha = 0.3f))) {
                        navController.navigate("experimental_hub")
                    }
                }
                // Odd tile out -- half-width row (paired with an empty
                // Spacer rather than stretching full-width) keeps the same
                // card size/rhythm as the 2x2 grid above instead of looking
                // like a broken layout.
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    ModuleCard("MY READING", "Habits", Icons.Default.Insights, Color(0xFF9ece6a), Modifier.weight(1f).cyberpunkGlowAura(time, Color(0xFF9ece6a).copy(alpha = 0.3f))) {
                        navController.navigate("reading_stats")
                    }
                    Spacer(modifier = Modifier.weight(1f))
                }
            }
        }
    }
}
