package com.bytecats.metanoia.ui.screens.settings

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.bytecats.metanoia.settings.SettingsManager

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AudioSettingsPage(navController: NavController, settings: SettingsManager) {
    var exp by remember { mutableStateOf(settings.useExperimentalTTS) }
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

            Text("TTS Engine", fontWeight = FontWeight.Bold, style = MaterialTheme.typography.titleMedium)
            Text(
                "Kokoro = lightweight neural (recommended)\nVoice Clone = Qwen3-TTS zero-shot cloning\nSystem = Android built-in (offline)",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.outline
            )

            SettingToggle("Experimental Voice Clone", "Use Qwen3-TTS neural cloning engine", exp) {
                exp = it
                settings.useExperimentalTTS = it
            }

            OutlinedTextField(
                value = voice,
                onValueChange = { voice = it; settings.selectedVoice = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Voice Profile") },
                placeholder = { Text("af_nicole") },
                singleLine = true,
                leadingIcon = { Icon(Icons.Default.RecordVoiceOver, null) }
            )
            Text(
                "Kokoro voices: af_nicole, af_heart, am_lennox, etc.\nClone voices: registered voice profile names from gateway.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.outline
            )

            HorizontalDivider()

            SettingToggle("Speak on Tap", "Narration for lexicon entries", talkTap) {
                talkTap = it
                settings.speakDefinitionsOnTap = it
            }

            Spacer(modifier = Modifier.height(8.dp))
            Text(
                "Server: ${settings.gatewayUrl}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.outline
            )
            Text(
                "Configure gateway IP/port in Settings > Gateway Connection",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.outline
            )
        }
    }
}
