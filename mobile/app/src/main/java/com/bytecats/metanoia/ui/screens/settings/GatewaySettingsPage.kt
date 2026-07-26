package com.bytecats.metanoia.ui.screens.settings

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.bytecats.metanoia.settings.SettingsManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GatewaySettingsPage(navController: NavController, settings: SettingsManager) {
    var gatewayIp by remember { mutableStateOf(settings.gatewayIp) }
    var gatewayPort by remember { mutableStateOf(settings.gatewayPort) }
    var useGatewayBible by remember { mutableStateOf(settings.useGatewayBible) }
    var connectionStatus by remember { mutableStateOf<String?>(null) }
    var isTesting by remember { mutableStateOf(false) }
    val scope = androidx.compose.runtime.rememberCoroutineScope()

    val fullUrl = "http://$gatewayIp:$gatewayPort"

    Scaffold(topBar = {
        TopAppBar(
            title = { Text("GATEWAY CONNECTION") },
            navigationIcon = {
                IconButton(onClick = { navController.popBackStack() }) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                }
            }
        )
    }) { innerPadding ->
        Column(
            modifier = Modifier.padding(innerPadding).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp)
        ) {
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

            SettingToggle(
                "Use Gateway Bible API",
                "Fetch verses, interlinear, and lexicon from gateway instead of direct scraping",
                useGatewayBible
            ) {
                useGatewayBible = it
                settings.useGatewayBible = it
            }

            HorizontalDivider()

            Text("Available Services", fontWeight = FontWeight.Bold, style = MaterialTheme.typography.titleMedium)
            ServiceItem("TTS - Kokoro Neural", "Neural text-to-speech, fast")
            ServiceItem("TTS - Voice Clone", "Qwen3-TTS zero-shot voice cloning")
            ServiceItem("STT - Whisper", "Speech transcription & verification")
            ServiceItem("Bible API", "84-book canon, interlinear, Strong's lexicon")
        }
    }
}
