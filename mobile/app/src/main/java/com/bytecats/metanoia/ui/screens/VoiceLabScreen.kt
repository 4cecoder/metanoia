package com.bytecats.metanoia.ui.screens

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bytecats.metanoia.tts.RemoteVoice
import com.bytecats.metanoia.viewmodel.MainViewModel
import java.io.File

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun VoiceLabScreen(viewModel: MainViewModel) {
    var text by remember { mutableStateOf("Metanoia: Neural synthesis check.") }
    var selectedVoiceKey by remember { mutableStateOf("") }
    var showCreateSheet by remember { mutableStateOf(false) }
    
    val logs = viewModel.voiceLogs
    val voices = viewModel.serverVoices
    val context = LocalContext.current
    
    val fileLauncher = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri: Uri? ->
        uri?.let {
            val file = File(context.cacheDir, "upload_temp.wav")
            context.contentResolver.openInputStream(it)?.use { input ->
                file.outputStream().use { output -> input.copyTo(output) }
            }
            if (selectedVoiceKey.isNotEmpty()) {
                viewModel.uploadVoiceSample(selectedVoiceKey, file)
            }
        }
    }

    Scaffold(
        topBar = { 
            TopAppBar(
                title = { Text("NEURAL STUDIO", fontWeight = FontWeight.Black) },
                actions = {
                    IconButton({ viewModel.refreshServerVoices() }) { Icon(Icons.Default.Refresh, null) }
                    IconButton({ viewModel.voiceLogs.clear() }) { Icon(Icons.Default.DeleteSweep, null, tint = Color.Red) }
                }
            ) 
        },
        floatingActionButton = {
            FloatingActionButton(onClick = { showCreateSheet = true }, containerColor = MaterialTheme.colorScheme.primary) {
                Icon(Icons.Default.Add, null)
            }
        }
    ) { innerPadding ->
        Column(modifier = Modifier.padding(innerPadding).fillMaxSize().padding(16.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            
            // Server Status Card
            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f))) {
                Column(Modifier.padding(16.dp).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(8.dp).background(if (voices.isNotEmpty()) Color(0xFF9ece6a) else Color.Red, CircleShape))
                        Spacer(Modifier.width(8.dp))
                        Text("CONTROL ENDPOINT", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
                    }
                    
                    var manualUrl by remember { mutableStateOf(viewModel.settingsManager.ttsServerUrl) }
                    OutlinedTextField(
                        value = manualUrl,
                        onValueChange = { 
                            manualUrl = it
                            viewModel.settingsManager.ttsServerUrl = it 
                        },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("Manual Overwrite (IP:PORT)") },
                        textStyle = LocalTextStyle.current.copy(fontFamily = FontFamily.Monospace, fontSize = 12.sp),
                        trailingIcon = {
                            IconButton({ viewModel.refreshServerVoices() }) { Icon(Icons.Default.Link, null) }
                        }
                    )

                    Button(
                        onClick = { viewModel.discoverServer() },
                        modifier = Modifier.fillMaxWidth(),
                        enabled = !viewModel.isDiscovering,
                        shape = RoundedCornerShape(8.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.secondary)
                    ) {
                        if (viewModel.isDiscovering) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp, color = Color.White)
                        else Text("AUTO-DISCOVER ON NETWORK")
                    }
                }
            }

            Text("INPUT ENGINE", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
            OutlinedTextField(text, { text = it }, modifier = Modifier.fillMaxWidth(), placeholder = { Text("Enter text to synthesize...") })

            Text("ARCHIVE MANAGEMENT", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
            
            voices.forEach { voice ->
                VoiceCard(
                    voice = voice,
                    isSelected = viewModel.settingsManager.selectedVoice == voice.key,
                    onSelect = { viewModel.settingsManager.selectedVoice = voice.key },
                    onDelete = { viewModel.deleteServerVoice(voice.key) },
                    onUpload = { 
                        viewModel.settingsManager.selectedVoice = voice.key
                        fileLauncher.launch("audio/wav") 
                    }
                )
            }

            if (viewModel.settingsManager.selectedVoice.isNotEmpty()) {
                Button(
                    onClick = { viewModel.speak(text) }, 
                    modifier = Modifier.fillMaxWidth().height(56.dp), 
                    shape = RoundedCornerShape(12.dp)
                ) { 
                    Icon(Icons.Default.Bolt, null); Spacer(Modifier.width(8.dp)); Text("INITIATE SYNTHESIS") 
                }
            }

            Text("TELEMETRY LOGS", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
            Box(modifier = Modifier.fillMaxWidth().height(200.dp).background(Color.Black, RoundedCornerShape(12.dp)).padding(12.dp)) {
                val s = rememberScrollState(); LaunchedEffect(logs.size) { s.animateScrollTo(s.maxValue) }
                Column(modifier = Modifier.verticalScroll(s)) { 
                    logs.forEach { Text(it, color = Color(0xFF9ece6a), fontFamily = FontFamily.Monospace, fontSize = 10.sp) } 
                }
            }
        }
    }

    if (showCreateSheet) {
        ModalBottomSheet(onDismissRequest = { showCreateSheet = false }) {
            var name by remember { mutableStateOf("") }
            var refText by remember { mutableStateOf("") }
            Column(Modifier.padding(24.dp).fillMaxWidth().padding(bottom = 40.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Text("Create Neural Profile", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                OutlinedTextField(name, { name = it }, label = { Text("Voice Name") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(refText, { refText = it }, label = { Text("Reference Text") }, modifier = Modifier.fillMaxWidth())
                Button(
                    onClick = { 
                        if (name.isNotEmpty()) {
                            viewModel.createServerVoice(name, refText)
                            showCreateSheet = false
                        }
                    },
                    modifier = Modifier.fillMaxWidth()
                ) { Text("Commit Placeholder") }
            }
        }
    }
}

@Composable
fun VoiceCard(
    voice: RemoteVoice,
    isSelected: Boolean,
    onSelect: () -> Unit,
    onDelete: () -> Unit,
    onUpload: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth().clickable { onSelect() },
        colors = CardDefaults.cardColors(
            containerColor = if (isSelected) MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.4f) 
                            else MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.2f)
        ),
        border = if (isSelected) BorderStroke(2.dp, MaterialTheme.colorScheme.primary) else null
    ) {
        Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(voice.displayName, fontWeight = FontWeight.Bold)
                Text(if (voice.exists) "READY" else "MISSING AUDIO", 
                    color = if (voice.exists) Color(0xFF9ece6a) else Color(0xFFf7768e),
                    style = MaterialTheme.typography.labelSmall
                )
            }
            if (voice.type == "cloned") {
                IconButton(onUpload) { Icon(Icons.Default.FileUpload, null, tint = MaterialTheme.colorScheme.primary) }
                IconButton(onDelete) { Icon(Icons.Default.Delete, null, tint = MaterialTheme.colorScheme.error) }
            } else {
                Icon(Icons.Default.Verified, null, tint = Color(0xFFbb9af7), modifier = Modifier.padding(12.dp))
            }
        }
    }
}
