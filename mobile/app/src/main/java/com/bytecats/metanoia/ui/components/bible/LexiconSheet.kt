package com.bytecats.metanoia.ui.components.bible

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.Diamond
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bytecats.metanoia.models.InterlinearWord
import com.bytecats.metanoia.models.LexiconEntry

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LexiconSheet(
    word: InterlinearWord,
    detail: LexiconEntry,
    onDismiss: () -> Unit,
    onSpeak: (String) -> Unit,
    onFavorite: (strongs: String, lemma: String, definition: String) -> Unit,
) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .padding(24.dp)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(
                        detail.lemma.ifEmpty { word.original },
                        style = MaterialTheme.typography.displaySmall,
                        fontWeight = FontWeight.Black,
                        color = MaterialTheme.colorScheme.primary
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        word.strongs,
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.secondary
                    )
                }
                IconButton({ onSpeak(detail.definition) }) {
                    Icon(
                        Icons.AutoMirrored.Filled.VolumeUp,
                        "Speak",
                        tint = MaterialTheme.colorScheme.primary
                    )
                }
                IconButton({ onFavorite(word.strongs, detail.lemma, detail.definition) }) {
                    Icon(
                        Icons.Default.Diamond,
                        "Pin",
                        tint = Color(0xFFbb9af7)
                    )
                }
            }
            HorizontalDivider(
                modifier = Modifier.padding(vertical = 24.dp),
                color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f)
            )
            Text(
                detail.definition,
                style = MaterialTheme.typography.bodyLarge,
                lineHeight = 24.sp
            )
            Spacer(modifier = Modifier.height(40.dp))
        }
    }
}
