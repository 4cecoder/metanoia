package com.bytecats.metanoia.ui.components.bible

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bytecats.metanoia.models.Note

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StudySheet(
    bookName: String,
    chapter: Int,
    verse: Int,
    notes: List<Note>,
    onDismiss: () -> Unit,
    onHighlight: (Int) -> Unit,
    onSaveNote: (String) -> Unit,
) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        var newNoteText by remember { mutableStateOf("") }
        Column(
            modifier = Modifier
                .padding(24.dp)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
        ) {
            Text(
                "$bookName $chapter:$verse",
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Black
            )
            Spacer(modifier = Modifier.height(16.dp))
            Text("Highlight Color", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary)
            Spacer(modifier = Modifier.height(8.dp))
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                listOf(0xFFFF9E6A, 0xFF9ECE6A, 0xFF7AA2F7, 0xFFBB9AF7, 0).forEach { color ->
                    val isTransparent = color.toLong() == 0L
                    Box(
                        modifier = Modifier
                            .size(48.dp)
                            .background(
                                if (isTransparent) MaterialTheme.colorScheme.surfaceVariant else Color(color.toLong()),
                                CircleShape
                            )
                            .border(
                                2.dp,
                                if (isTransparent) MaterialTheme.colorScheme.outline else Color.Transparent,
                                CircleShape
                            )
                            .clickable { onHighlight(color.toInt()) },
                        contentAlignment = Alignment.Center
                    ) {
                        if (isTransparent) {
                            Icon(
                                Icons.Default.Close,
                                contentDescription = "Clear Highlight",
                                tint = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }
            }
            Spacer(modifier = Modifier.height(32.dp))
            Text("Study Notes", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary)
            Spacer(modifier = Modifier.height(8.dp))
            notes.forEach { note ->
                Card(
                    modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.surfaceVariant
                    )
                ) {
                    Text(
                        note.content,
                        modifier = Modifier.padding(12.dp),
                        style = MaterialTheme.typography.bodyMedium
                    )
                }
            }
            OutlinedTextField(
                value = newNoteText,
                onValueChange = { newNoteText = it },
                modifier = Modifier.fillMaxWidth(),
                placeholder = { Text("Enter insight...") }
            )
            Button(
                onClick = {
                    if (newNoteText.isNotEmpty()) {
                        onSaveNote(newNoteText)
                        newNoteText = ""
                    }
                },
                modifier = Modifier.align(Alignment.End).padding(top = 8.dp)
            ) {
                Text("Save Note")
            }
            Spacer(modifier = Modifier.height(40.dp))
        }
    }
}
