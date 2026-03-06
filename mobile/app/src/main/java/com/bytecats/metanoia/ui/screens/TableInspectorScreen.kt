package com.bytecats.metanoia.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.bytecats.metanoia.bible.BibleManager
import com.bytecats.metanoia.models.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TableInspectorScreen(tableName: String, bible: BibleManager) {
    val rows = remember { bible.getTableRows(tableName) }
    Scaffold(topBar = { TopAppBar(title = { Text("INSPECT: $tableName") }) }) { innerPadding ->
        if (rows.isEmpty()) { 
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { 
                Text("No records found in $tableName", color = MaterialTheme.colorScheme.outline) 
            } 
        } else {
            val columns = rows.first().keys.toList()
            Column(modifier = Modifier.padding(innerPadding).fillMaxSize().horizontalScroll(rememberScrollState())) {
                Row(modifier = Modifier.background(MaterialTheme.colorScheme.primaryContainer).padding(8.dp)) {
                    columns.forEach { col -> 
                        Text(col, modifier = Modifier.width(120.dp).padding(4.dp), fontWeight = FontWeight.Black, style = MaterialTheme.typography.labelSmall) 
                    }
                }
                LazyColumn {
                    items(rows) { row ->
                        Row(modifier = Modifier.padding(8.dp)) {
                            columns.forEach { col -> 
                                Text(row[col] ?: "NULL", modifier = Modifier.width(120.dp).padding(4.dp), style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis) 
                            }
                        }
                        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(0.3f))
                    }
                }
            }
        }
    }
}
