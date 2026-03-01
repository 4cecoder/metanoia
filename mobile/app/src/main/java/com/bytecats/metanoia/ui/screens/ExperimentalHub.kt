package com.bytecats.metanoia.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.bytecats.metanoia.ui.components.ModuleCard

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExperimentalHub(navController: NavController) {
    Scaffold(topBar = { TopAppBar(title = { Text("EXPERIMENTAL HUB") }) }) { innerPadding ->
        Column(modifier = Modifier.padding(innerPadding).fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            ModuleCard("GRANITE-4 AI", "IBM 350M Ultra-Fast", Icons.Default.AutoAwesome, Color(0xFF7aa2f7)) { 
                navController.navigate("ai_lab") 
            }
            ModuleCard("VOICE LAB", "TPU Voice & Cloning", Icons.Default.GraphicEq, Color(0xFF9ece6a)) { 
                navController.navigate("voice_lab") 
            }
        }
    }
}
