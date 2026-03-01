package com.bytecats.metanoia.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoMode
import androidx.compose.material.icons.filled.DeleteSweep
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.bytecats.metanoia.ui.components.ConfirmActionDialog
import com.bytecats.metanoia.ui.components.StatItemCompact
import com.bytecats.metanoia.viewmodel.MainViewModel
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DataManagementScreen(navController: NavController, viewModel: MainViewModel) {
    val bible = viewModel.bibleManager
    var stats by remember { mutableStateOf(bible.getStats()) }
    var integrity by remember { mutableStateOf("Ready") }
    var showConfirm by remember { mutableStateOf<Pair<String, () -> Unit>?>(null) }
    val scope = rememberCoroutineScope()

    Scaffold(topBar = { TopAppBar(title = { Text("DATA COMMAND CENTER") }) }) { innerPadding ->
        Column(modifier = Modifier.padding(innerPadding).fillMaxSize().padding(16.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(20.dp)) {
            Text("LIBRARY INSIGHTS", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
            Card(modifier = Modifier.fillMaxWidth(), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.2f))) {
                Column(modifier = Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) { 
                        StatItemCompact("OT Verses", "${stats.versesOt}")
                        StatItemCompact("NT Verses", "${stats.versesNt}") 
                    }
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) { 
                        StatItemCompact("Lexicon", "${stats.lexiconHeb + stats.lexiconGk}")
                        StatItemCompact("Insights", "${stats.notesCount}") 
                    }
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) { 
                        Text("Storage Health", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.outline)
                        Text("%.2f MB".format(stats.dbSizeMb), color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.Black) 
                    }
                }
            }

            Text("ENGINE CONTROL", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.outline)
            Card(modifier = Modifier.fillMaxWidth(), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f))) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) { 
                        Text("Integrity Status:")
                        Text(integrity, color = if (integrity == "ok") Color(0xFF9ece6a) else MaterialTheme.colorScheme.primary, fontWeight = FontWeight.Black) 
                    }
                    Button(onClick = { scope.launch { integrity = bible.checkIntegrity(); bible.vacuumDatabase(); stats = bible.getStats() } }, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(12.dp)) { 
                        Icon(Icons.Default.AutoMode, null); Spacer(Modifier.width(8.dp)); Text("OPTIMIZE & REINDEX") 
                    }
                }
            }

            Text("GRANULAR MANAGEMENT", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.outline)
            TableCard("verses", stats.versesOt + stats.versesNt, { navController.navigate("table_inspector/verses") }) { showConfirm = "Verse Library" to { bible.clearTable("verses"); stats = bible.getStats() } }
            TableCard("lexicon", stats.lexiconHeb + stats.lexiconGk, { navController.navigate("table_inspector/lexicon") }) { showConfirm = "Lexical Data" to { bible.clearTable("lexicon"); stats = bible.getStats() } }
            TableCard("interlinear", stats.interlinearCount, { navController.navigate("table_inspector/interlinear") }) { showConfirm = "Interlinear Mapping" to { bible.clearTable("interlinear"); stats = bible.getStats() } }
            TableCard("notes", stats.notesCount, { navController.navigate("table_inspector/notes") }) { showConfirm = "User Insights" to { bible.clearTable("notes"); stats = bible.getStats() } }
            
            Spacer(Modifier.height(24.dp))
            Button(onClick = { showConfirm = "FACTORY RESET EVERYTHING" to { bible.factoryReset(); stats = bible.getStats() } }, modifier = Modifier.fillMaxWidth().height(64.dp), colors = ButtonDefaults.buttonColors(containerColor = Color.Red), shape = RoundedCornerShape(16.dp)) { 
                Text("FACTORY RESET DB", fontWeight = FontWeight.Black) 
            }
        }
    }
    showConfirm?.let { (target, action) -> 
        ConfirmActionDialog(title = "Wipe $target?", msg = "This action is irreversible.", onConfirm = action, onDismiss = { showConfirm = null }) 
    }
}

@Composable
fun TableCard(name: String, count: Int, onView: () -> Unit, onWipe: () -> Unit) {
    Card(modifier = Modifier.fillMaxWidth(), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f))) { 
        Row(modifier = Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) { 
            Column(modifier = Modifier.weight(1f)) { 
                Text(name.uppercase(), fontWeight = FontWeight.Bold)
                Text("$count records", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.outline) 
            }
            IconButton(onClick = onView) { Icon(Icons.Default.Visibility, null, tint = MaterialTheme.colorScheme.primary) }
            IconButton(onClick = onWipe) { Icon(Icons.Default.DeleteSweep, null, tint = Color.Red) } 
        } 
    }
}
