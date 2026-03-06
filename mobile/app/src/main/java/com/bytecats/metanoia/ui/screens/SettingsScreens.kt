package com.bytecats.metanoia.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForwardIos
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.bytecats.metanoia.settings.SettingsManager

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsDashboard(navController: NavController) {
    Scaffold(topBar = { TopAppBar(title = { Text("SETTINGS") }) }) { innerPadding ->
        Column(modifier = Modifier.padding(innerPadding).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            SettingsLink("Voice & Audio", "System TTS and NPU", Icons.Default.VolumeUp) { 
                navController.navigate("settings_audio") 
            }
            SettingsLink("Reader Styles", "Fonts and Haptics", Icons.Default.TextFormat) { 
                navController.navigate("settings_reader") 
            }
            SettingsLink("Data & Library", "Database Management", Icons.Default.Storage) { 
                navController.navigate("data_management") 
            }
        }
    }
}

@Composable
fun SettingsLink(title: String, subtitle: String, icon: ImageVector, onClick: () -> Unit) {
    Card(modifier = Modifier.fillMaxWidth().clickable { onClick() }, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f))) {
        Row(modifier = Modifier.padding(20.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, null, tint = MaterialTheme.colorScheme.primary)
            Spacer(modifier = Modifier.width(16.dp))
            Column {
                Text(title, fontWeight = FontWeight.Bold)
                Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.outline)
            }
            Spacer(modifier = Modifier.weight(1f))
            Icon(Icons.AutoMirrored.Filled.ArrowForwardIos, null, modifier = Modifier.size(16.dp))
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AudioSettingsPage(settings: SettingsManager) {
    var exp by remember { mutableStateOf(settings.useExperimentalTTS) }
    var talkTap by remember { mutableStateOf(settings.speakDefinitionsOnTap) }
    var serverUrl by remember { mutableStateOf(settings.ttsServerUrl) }
    
    Scaffold(topBar = { TopAppBar(title = { Text("AUDIO ENGINE") }) }) { innerPadding ->
        Column(modifier = Modifier.padding(innerPadding).padding(16.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
            SettingToggle("Experimental Remote TTS", "Enable Qwen3-TTS Neural Engine", exp) { 
                exp = it; settings.useExperimentalTTS = it 
            }
            
            if (exp) {
                OutlinedTextField(
                    value = serverUrl,
                    onValueChange = { serverUrl = it; settings.ttsServerUrl = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("TTS Server URL") },
                    placeholder = { Text("http://192.168.1.xxx:8000") }
                )
                Text("Specify the remote server address or use auto-discovery.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.outline)
            }
            
            SettingToggle("Speak on Tap", "Narration for lexicon entries", talkTap) { 
                talkTap = it; settings.speakDefinitionsOnTap = it 
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReaderSettingsPage(settings: SettingsManager) {
    var engSize by remember { mutableStateOf(settings.englishFontSize.toFloat()) }
    var ancSize by remember { mutableStateOf(settings.ancientFontSize.toFloat()) }
    Scaffold(topBar = { TopAppBar(title = { Text("READER STYLES") }) }) { innerPadding ->
        Column(modifier = Modifier.padding(innerPadding).padding(16.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
            Text("English Font Size: ${engSize.toInt()}px")
            Slider(engSize, { engSize = it; settings.englishFontSize = it.toInt() }, valueRange = 14f..40f)
            Text("Ancient Font Size: ${ancSize.toInt()}px")
            Slider(ancSize, { ancSize = it; settings.ancientFontSize = it.toInt() }, valueRange = 14f..40f)
        }
    }
}

@Composable
fun SettingToggle(title: String, sub: String, state: Boolean, onToggle: (Boolean) -> Unit) {
    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Column(modifier = Modifier.weight(1f)) {
            Text(title, fontWeight = FontWeight.Bold)
            Text(sub, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.outline)
        }
        Switch(state, onToggle)
    }
}
