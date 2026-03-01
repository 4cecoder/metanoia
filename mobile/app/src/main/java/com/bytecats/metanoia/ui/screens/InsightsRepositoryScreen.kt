package com.bytecats.metanoia.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.bytecats.metanoia.viewmodel.MainViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InsightsRepositoryScreen(viewModel: MainViewModel, onTts: (String) -> Unit) {
    val stats = remember { viewModel.bibleManager.getStats() }
    Scaffold(topBar = { TopAppBar(title = { Text("MY INSIGHT REPOSITORY") }) }) { innerPadding ->
        if (stats.notesCount == 0) { 
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { 
                Text("No insights recorded yet.", color = MaterialTheme.colorScheme.outline) 
            } 
        } else { 
            Box(modifier = Modifier.padding(innerPadding).fillMaxSize(), contentAlignment = Alignment.Center) { 
                Text("${stats.notesCount} insights secured in library.", color = MaterialTheme.colorScheme.primary) 
            } 
        }
    }
}
