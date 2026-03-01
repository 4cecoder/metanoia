package com.bytecats.metanoia.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bytecats.metanoia.llm.AIProvider
import com.bytecats.metanoia.llm.LLMManager
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GraniteLabScreen(logs: List<String>, llm: LLMManager) {
    var query by remember { mutableStateOf("") }
    val chat = remember { mutableStateListOf<Pair<String, String>>() }
    val scope = rememberCoroutineScope()
    val scroll = rememberScrollState()
    
    val provider by llm.provider.collectAsState()
    val status by llm.status.collectAsState()
    val isBusy by llm.isBusy.collectAsState()
    val progress by llm.downloadProgress.collectAsState()
    val isLoaded = llm.isModelLoaded()

    var showConfig by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        if (!isLoaded && llm.modelExists()) llm.loadModel()
    }

    Scaffold(topBar = { 
        TopAppBar(
            title = { Text("AI LAB") },
            actions = {
                IconButton({ showConfig = !showConfig }) { Icon(Icons.Default.Settings, "Configure Ollama") }
                IconButton({ 
                    val next = if (provider == AIProvider.LOCAL_TPU) AIProvider.OLLAMA else AIProvider.LOCAL_TPU
                    llm.setProvider(next)
                }) { 
                    Icon(if (provider == AIProvider.LOCAL_TPU) Icons.Default.Dns else Icons.Default.Cloud, null)
                }
            }
        ) 
    }) { innerPadding ->
        Column(modifier = Modifier.padding(innerPadding).fillMaxSize().padding(16.dp)) {
            // HIGH-FIDELITY DEBUG TERMINAL
            Text("ENGINE: ${provider.name} | $status", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
            Box(modifier = Modifier.weight(0.25f).fillMaxWidth().padding(top = 4.dp).background(Color.Black, RoundedCornerShape(12.dp)).padding(12.dp)) {
                val s = rememberScrollState()
                LaunchedEffect(logs.size) { s.animateScrollTo(s.maxValue) }
                Column(modifier = Modifier.verticalScroll(s)) { 
                    logs.forEach { Text(it, color = if (it.contains("ERR")) Color(0xFFf7768e) else Color(0xFF7aa2f7), fontFamily = FontFamily.Monospace, fontSize = 10.sp) } 
                }
            }

            if (showConfig) {
                Card(modifier = Modifier.padding(top = 12.dp).fillMaxWidth(), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) {
                    Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("OLLAMA CONFIG", fontWeight = FontWeight.Bold)
                        OutlinedTextField(llm.ollamaUrl, { llm.ollamaUrl = it }, label = { Text("Server URL") }, modifier = Modifier.fillMaxWidth())
                        OutlinedTextField(llm.ollamaModel, { llm.ollamaModel = it }, label = { Text("Model Name") }, modifier = Modifier.fillMaxWidth())
                        Button({ showConfig = false }, modifier = Modifier.align(Alignment.End)) { Text("Save & Close") }
                    }
                }
            }

            if (provider == AIProvider.LOCAL_TPU && !isLoaded) {
                Column(modifier = Modifier.weight(0.75f).fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(if (isBusy) Icons.Default.CloudDownload else Icons.Default.HistoryEdu, null, modifier = Modifier.size(64.dp), tint = MaterialTheme.colorScheme.primary)
                    Spacer(Modifier.height(16.dp))
                    Text(if (isBusy) "SYNCING SCHOLAR ENGINE" else "GRANITE-4:350M OFFLINE", fontWeight = FontWeight.Black, style = MaterialTheme.typography.titleMedium)
                    Text("Tensor G4 TPU Accelerated", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.outline)
                    Spacer(Modifier.height(24.dp))
                    
                    if (isBusy) {
                        LinearProgressIndicator(progress = { progress }, modifier = Modifier.fillMaxWidth().height(12.dp), strokeCap = StrokeCap.Round)
                        Text("${(progress * 100).toInt()}%", modifier = Modifier.padding(top = 8.dp), fontWeight = FontWeight.Black, style = MaterialTheme.typography.headlineSmall)
                    } else {
                        Button(onClick = { if (llm.modelExists()) llm.loadModel() else scope.launch { llm.downloadModel() } }, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(12.dp)) {
                            Text(if (llm.modelExists()) "INITIALIZE ENGINE" else "DOWNLOAD LOCAL SCHOLAR (220MB)", fontWeight = FontWeight.Bold)
                        }
                    }
                }
            } else {
                Column(modifier = Modifier.weight(0.75f).padding(top = 12.dp).verticalScroll(scroll), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (chat.isEmpty()) { Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Text(if (provider == AIProvider.LOCAL_TPU) "Local Scholarship Active" else "Network Scholarship Active", color = MaterialTheme.colorScheme.outline) } }
                    chat.forEach { (who, msg) ->
                        Card(modifier = Modifier.fillMaxWidth().padding(end = if (who == "User") 32.dp else 0.dp, start = if (who == "AI") 32.dp else 0.dp), colors = CardDefaults.cardColors(containerColor = if (who == "User") MaterialTheme.colorScheme.surfaceVariant else MaterialTheme.colorScheme.primaryContainer.copy(0.2f))) {
                            Column(modifier = Modifier.padding(12.dp)) { Text(who, fontWeight = FontWeight.Bold, style = MaterialTheme.typography.labelSmall); Text(msg) }
                        }
                    }
                }
                Row(modifier = Modifier.padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                    OutlinedTextField(query, { query = it }, modifier = Modifier.weight(1f), placeholder = { Text("Research with ${provider.name}...") }, shape = RoundedCornerShape(24.dp), enabled = !isBusy)
                    IconButton(onClick = { 
                        val q = query; query = ""; chat.add("User" to q); chat.add("AI" to "..."); 
                        scope.launch { var r = ""; llm.generateResponse(q).collect { chunk -> r += chunk; chat[chat.size - 1] = "AI" to r } } 
                    }, modifier = Modifier.padding(start = 8.dp).background(MaterialTheme.colorScheme.primary, CircleShape), enabled = !isBusy) { 
                        Icon(Icons.AutoMirrored.Filled.Send, null, tint = Color.White) 
                    }
                }
            }
        }
    }
}
