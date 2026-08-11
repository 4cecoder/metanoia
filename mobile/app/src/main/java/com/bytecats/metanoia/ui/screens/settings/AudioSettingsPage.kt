package com.bytecats.metanoia.ui.screens.settings

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.bytecats.metanoia.settings.SettingsManager

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AudioSettingsPage(navController: NavController, settings: SettingsManager) {
    var talkTap by remember { mutableStateOf(settings.speakDefinitionsOnTap) }
    var voice by remember { mutableStateOf(settings.selectedVoice) }

    Scaffold(topBar = {
        TopAppBar(
            title = { Text("AUDIO ENGINE") },
            navigationIcon = {
                IconButton(onClick = { navController.popBackStack() }) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                }
            }
        )
    }) { innerPadding ->
        Column(modifier = Modifier.padding(innerPadding).padding(16.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {

            // NATIVE TTS NOTICE
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer)
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.CheckCircle, null, tint = MaterialTheme.colorScheme.primary)
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(
                            "Native Neural TTS",
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.primary
                        )
                    }
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        "Using Qwen3-TTS forward pass with GGUF models - no gateway required!",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.primary
                    )
                    Text(
                        "Supported: Neural synthesis, voice cloning via GGUF, 24kHz audio output",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.primary
                    )
                }
            }

            Text("TTS Engine", fontWeight = FontWeight.Bold, style = MaterialTheme.typography.titleMedium)
            Text(
                "Native = Qwen3-TTS neural (recommended, offline)\nGateway = Remote gateway (deprecated, unused)",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.outline
            )

            OutlinedTextField(
                value = voice,
                onValueChange = { voice = it; settings.selectedVoice = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Voice Model") },
                placeholder = { Text("qwen_tts_2b.gguf") },
                singleLine = true,
                leadingIcon = { Icon(Icons.Default.RecordVoiceOver, null) }
            )
            Text(
                "GGUF voice models: qwen_tts_2b.gguf, custom voices via VoiceLab\nLoad from app data directory or VoiceLab interface.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.outline
            )

            HorizontalDivider()

            SettingToggle("Speak on Tap", "Narration for lexicon entries", talkTap) {
                talkTap = it
                settings.speakDefinitionsOnTap = it
            }

            Spacer(modifier = Modifier.height(8.dp))
            
            // DEPRECATED GATEWAY REFERENCE
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer.copy(0.3f))
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.Warning, null, tint = MaterialTheme.colorScheme.error)
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(
                            "Gateway Settings",
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.error
                        )
                    }
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        "Legacy Gateway URL: ${settings.gatewayUrl}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onErrorContainer
                    )
                    Text(
                        "⚠️ Gateway settings are deprecated. Use native GGUF models.",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onErrorContainer
                    )
                }
            }
        }
    }
}
