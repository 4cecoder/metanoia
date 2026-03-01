package com.bytecats.metanoia.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bytecats.metanoia.bible.BibleManager
import com.bytecats.metanoia.ui.components.StatItemCompact

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LibraryStatsScreen(bible: BibleManager) {
    val stats = remember { bible.getStats() }
    Scaffold(topBar = { TopAppBar(title = { Text("LIBRARY ANALYTICS") }) }) { innerPadding ->
        Column(modifier = Modifier.padding(innerPadding).fillMaxSize().padding(24.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(20.dp)) {
            Text("SCRIPTORIUM METRICS", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
            Card(modifier = Modifier.fillMaxWidth(), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.2f))) {
                Column(modifier = Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
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
                        Text("Disk Usage", fontWeight = FontWeight.Bold)
                        Text("%.2f MB".format(stats.dbSizeMb), color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.Black)
                    }
                }
            }
        }
    }
}
