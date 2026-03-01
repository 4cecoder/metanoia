package com.bytecats.metanoia.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun VoiceLabScreen(logs: List<String>, onGenerate: (String, String) -> Unit, onClear: () -> Unit) {
    var text by remember { mutableStateOf("Metanoia: High-fidelity speech.") }
    var voice by remember { mutableStateOf("John Lennox") }
    
    Scaffold(topBar = { 
        TopAppBar(
            title = { Text("VOICE PLAYGROUND") }, 
            actions = { IconButton(onClear) { Icon(Icons.Default.Delete, null, tint = Color.Red) } }
        ) 
    }) { innerPadding ->
        Column(modifier = Modifier.padding(innerPadding).fillMaxSize().padding(20.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(20.dp)) {
            Text("INPUT ENGINE", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
            OutlinedTextField(text, { text = it }, modifier = Modifier.fillMaxWidth(), label = { Text("TTS Text") })
            Text("DEMO VOICES", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
            FlowRow(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf("John Lennox", "Sam Shamoun", "Tommy", "Jordan Peterson").forEach { v -> 
                    FilterChip(selected = (voice == v), onClick = { voice = v }, label = { Text(v) }) 
                }
            }
            Button({ onGenerate(text, voice) }, modifier = Modifier.fillMaxWidth().height(64.dp), shape = RoundedCornerShape(12.dp)) { 
                Icon(Icons.Default.GraphicEq, null); Spacer(Modifier.width(8.dp)); Text("GENERATE ON TPU") 
            }
            Text("ANALYTICS", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
            Box(modifier = Modifier.fillMaxWidth().height(250.dp).background(Color.Black, RoundedCornerShape(12.dp)).padding(12.dp)) {
                val s = rememberScrollState(); LaunchedEffect(logs.size) { s.animateScrollTo(s.maxValue) }
                Column(modifier = Modifier.verticalScroll(s)) { 
                    logs.forEach { Text(it, color = Color(0xFF9ece6a), fontFamily = FontFamily.Monospace, fontSize = 10.sp) } 
                }
            }
        }
    }
}
