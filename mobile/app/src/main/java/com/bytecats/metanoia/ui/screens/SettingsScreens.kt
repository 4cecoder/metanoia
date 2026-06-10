package com.bytecats.metanoia.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForwardIos
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.bytecats.metanoia.settings.SettingsManager
import com.bytecats.metanoia.viewmodel.MainViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsDashboard(navController: NavController) {
    Scaffold(topBar = { TopAppBar(title = { Text("SETTINGS") }) }) { innerPadding ->
        Column(modifier = Modifier.padding(innerPadding).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            SettingsLink("Gateway Connection", "AI VM Server IP & Port", Icons.Default.Dns) {
                navController.navigate("settings_gateway")
            }
            SettingsLink("Voice & Audio", "TTS Engine and Voice", Icons.Default.VolumeUp) {
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

// -----------------------------------------------------------------------
// Gateway Connection Settings
// -----------------------------------------------------------------------

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GatewaySettingsPage(settings: SettingsManager) {
    var gatewayIp by remember { mutableStateOf(settings.gatewayIp) }
    var gatewayPort by remember { mutableStateOf(settings.gatewayPort) }
    var useGatewayBible by remember { mutableStateOf(settings.useGatewayBible) }
    var connectionStatus by remember { mutableStateOf<String?>(null) }
    var isTesting by remember { mutableStateOf(false) }
    val scope = androidx.compose.runtime.rememberCoroutineScope()

    val fullUrl = "http://$gatewayIp:$gatewayPort"

    Scaffold(topBar = { TopAppBar(title = { Text("GATEWAY CONNECTION") }) }) { innerPadding ->
        Column(
            modifier = Modifier.padding(innerPadding).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp)
        ) {
            // IP Address
            OutlinedTextField(
                value = gatewayIp,
                onValueChange = {
                    gatewayIp = it
                    settings.gatewayIp = it
                    connectionStatus = null
                },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Gateway IP Address") },
                placeholder = { Text("192.168.122.2") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                leadingIcon = { Icon(Icons.Default.Router, null) }
            )

            // Port
            OutlinedTextField(
                value = gatewayPort,
                onValueChange = {
                    gatewayPort = it.filter { c -> c.isDigit() }
                    settings.gatewayPort = gatewayPort
                    connectionStatus = null
                },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Port") },
                placeholder = { Text("8000") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                leadingIcon = { Icon(Icons.Default.Lan, null) }
            )

            // Current URL display
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(0.3f))
            ) {
                Row(
                    modifier = Modifier.padding(16.dp).fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Default.Link, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(20.dp))
                    Spacer(modifier = Modifier.width(12.dp))
                    Text(fullUrl, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
                    if (isTesting) {
                        CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                    } else {
                        connectionStatus?.let { status ->
                            Icon(
                                if (status == "Connected") Icons.Default.CheckCircle else Icons.Default.Error,
                                null,
                                tint = if (status == "Connected") MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error,
                                modifier = Modifier.size(20.dp)
                            )
                        }
                    }
                }
            }

            // Test connection button
            Button(
                onClick = {
                    isTesting = true
                    connectionStatus = null
                    scope.launch {
                        val url = "http://${settings.gatewayIp}:${settings.gatewayPort}"
                        val ok = withContext(Dispatchers.IO) {
                            try {
                                val req = okhttp3.Request.Builder().url("$url/health").get().build()
                                okhttp3.OkHttpClient.Builder()
                                    .connectTimeout(5, java.util.concurrent.TimeUnit.SECONDS)
                                    .build()
                                    .newCall(req).execute().use { it.isSuccessful }
                            } catch (e: Exception) { false }
                        }
                        connectionStatus = if (ok) "Connected" else "Failed"
                        isTesting = false
                    }
                },
                modifier = Modifier.fillMaxWidth(),
                enabled = !isTesting && gatewayIp.isNotBlank() && gatewayPort.isNotBlank()
            ) {
                Icon(Icons.Default.WifiTethering, null, modifier = Modifier.size(20.dp))
                Spacer(modifier = Modifier.width(8.dp))
                Text("Test Connection")
            }

            connectionStatus?.let { status ->
                Text(
                    if (status == "Connected") "Gateway is online and responding!" else "Could not reach gateway. Check IP/Port.",
                    style = MaterialTheme.typography.bodySmall,
                    color = if (status == "Connected") MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error
                )
            }

            HorizontalDivider()

            // Gateway Bible toggle
            SettingToggle(
                "Use Gateway Bible API",
                "Fetch verses, interlinear, and lexicon from gateway instead of direct scraping",
                useGatewayBible
            ) {
                useGatewayBible = it
                settings.useGatewayBible = it
            }

            HorizontalDivider()

            // Available services
            Text("Available Services", fontWeight = FontWeight.Bold, style = MaterialTheme.typography.titleMedium)
            ServiceItem("TTS - Kokoro Neural", "Neural text-to-speech, fast")
            ServiceItem("TTS - Voice Clone", "Qwen3-TTS zero-shot voice cloning")
            ServiceItem("STT - Whisper", "Speech transcription & verification")
            ServiceItem("Bible API", "84-book canon, interlinear, Strong's lexicon")
        }
    }
}

@Composable
fun ServiceItem(name: String, description: String) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(Icons.Default.Check, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(16.dp))
        Spacer(modifier = Modifier.width(12.dp))
        Column {
            Text(name, fontWeight = FontWeight.Medium, style = MaterialTheme.typography.bodyMedium)
            Text(description, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.outline)
        }
    }
}

// -----------------------------------------------------------------------
// Audio Settings
// -----------------------------------------------------------------------

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AudioSettingsPage(settings: SettingsManager) {
    var exp by remember { mutableStateOf(settings.useExperimentalTTS) }
    var talkTap by remember { mutableStateOf(settings.speakDefinitionsOnTap) }
    var voice by remember { mutableStateOf(settings.selectedVoice) }

    Scaffold(topBar = { TopAppBar(title = { Text("AUDIO ENGINE") }) }) { innerPadding ->
        Column(modifier = Modifier.padding(innerPadding).padding(16.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {

            // TTS Mode selector
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

// -----------------------------------------------------------------------
// Reader Settings
// -----------------------------------------------------------------------

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
