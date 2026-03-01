package com.bytecats.metanoia.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.bytecats.metanoia.viewmodel.MainViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CollectionScreen(viewModel: MainViewModel) {
    var tabIndex by remember { mutableStateOf(0) }
    val favs = remember { viewModel.bibleManager.getFavorites() }
    
    Scaffold(topBar = {
        TopAppBar(title = { Text("MY COLLECTION") })
    }) { innerPadding ->
        Column(modifier = Modifier.padding(innerPadding).fillMaxSize()) {
            PrimaryTabRow(selectedTabIndex = tabIndex) {
                Tab(selected = tabIndex == 0, onClick = { tabIndex = 0 }, text = { Text("TREASURE (LEX)") })
                Tab(selected = tabIndex == 1, onClick = { tabIndex = 1 }, text = { Text("INSIGHTS (NOTES)") })
            }
            if (tabIndex == 0) {
                if (favs.isEmpty()) { 
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { 
                        Text("No treasures pinned.", color = MaterialTheme.colorScheme.outline) 
                    } 
                } else { 
                    LazyColumn(modifier = Modifier.fillMaxSize().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) { 
                        items(favs) { f -> 
                            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f))) { 
                                Column(modifier = Modifier.padding(20.dp)) { 
                                    Row(verticalAlignment = Alignment.CenterVertically) { 
                                        Column(modifier = Modifier.weight(1f)) { 
                                            Text(f.lemma, fontWeight = FontWeight.Bold, style = MaterialTheme.typography.titleLarge)
                                            Text(f.strongs, style = MaterialTheme.typography.labelSmall) 
                                        }
                                        IconButton({ viewModel.speak(f.definition) }) { Icon(Icons.AutoMirrored.Filled.VolumeUp, "Speak") } 
                                    }
                                    Text(f.definition, maxLines = 3, overflow = TextOverflow.Ellipsis) 
                                } 
                            } 
                        } 
                    } 
                }
            } else {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { 
                    Text("Personal scholarly insights repository.", color = MaterialTheme.colorScheme.outline) 
                }
            }
        }
    }
}
