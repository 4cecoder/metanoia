package com.bytecats.metanoia.ui.components.bible

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.Smartphone
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bytecats.metanoia.models.RemoteVoice

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun VoiceSheet(
    serverVoices: List<RemoteVoice>,
    initialUseRemote: Boolean,
    initialVoice: String,
    onDismiss: () -> Unit,
    onToggleRemote: (Boolean) -> Unit,
    onSelectVoice: (String) -> Unit,
) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        var useRemote by remember { mutableStateOf(initialUseRemote) }
        var selectedVoice by remember { mutableStateOf(initialVoice) }

        Column(
            modifier = Modifier
                .padding(24.dp)
                .fillMaxWidth()
                .padding(bottom = 40.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp)
        ) {
            Text(
                "VOICE SETTINGS",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Black
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                FilterChip(
                    selected = !useRemote,
                    onClick = { useRemote = false; onToggleRemote(false) },
                    label = { Text("Standard") },
                    leadingIcon = { Icon(Icons.Default.Smartphone, null, Modifier.size(16.dp)) }
                )
                FilterChip(
                    selected = useRemote,
                    onClick = { useRemote = true; onToggleRemote(true) },
                    label = { Text("Neural") },
                    leadingIcon = { Icon(Icons.Default.Cloud, null, Modifier.size(16.dp)) }
                )
            }

            if (useRemote) {
                Text(
                    "SELECT NEURAL VOICE",
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.primary
                )
                FlowRow(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    serverVoices.forEach { voice ->
                        FilterChip(
                            selected = (selectedVoice == voice.key),
                            onClick = {
                                selectedVoice = voice.key
                                onSelectVoice(voice.key)
                            },
                            label = { Text(voice.displayName) },
                            enabled = voice.exists
                        )
                    }
                }
            } else {
                Text(
                    "Using system-native synthesis.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.outline
                )
            }

            Button(
                onClick = onDismiss,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("Apply Settings")
            }
        }
    }
}
