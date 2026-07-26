package com.bytecats.metanoia.ui.components.bible

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.bytecats.metanoia.models.BibleBook

/**
 * Book picker grid showing Old/New/Eth testament sections with download
 * completion borders and read-progress gradient fills.
 */
@Composable
fun BookGrid(
    books: List<BibleBook>,
    completionMap: Map<String, Float>,
    readCompletionMap: Map<String, Float>,
    showEthiopianCanon: Boolean,
    showApocrypha: Boolean,
    onBookSelected: (BibleBook) -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyVerticalGrid(
        columns = GridCells.Fixed(3),
        modifier = modifier.padding(12.dp)
    ) {
        listOf("Old" to "Old Testament", "New" to "New Testament", "Eth" to "Ethiopian")
            .filter { (key, _) -> key != "Eth" || showEthiopianCanon }
            .forEach { (key, label) ->
                item(span = { GridItemSpan(maxLineSpan) }) {
                    Text(
                        label,
                        modifier = Modifier.padding(16.dp),
                        color = MaterialTheme.colorScheme.primary,
                        fontWeight = FontWeight.Bold
                    )
                }
                items(books.filter { it.testament == key && (showApocrypha || !it.isApocrypha) }) { book ->
                    BookCard(
                        book = book,
                        progress = completionMap[book.name] ?: 0f,
                        readProgress = readCompletionMap[book.name] ?: 0f,
                        onClick = { onBookSelected(book) }
                    )
                }
            }
    }
}

@Composable
private fun BookCard(
    book: BibleBook,
    progress: Float,
    readProgress: Float,
    onClick: () -> Unit,
) {
    val unreadTone = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f)
    val readTone = Color(0xFF9ece6a).copy(alpha = 0.5f)
    val edge = readProgress.coerceIn(0f, 1f)
    val fillBrush = Brush.horizontalGradient(
        colorStops = arrayOf(
            0f to readTone,
            (edge - 0.02f).coerceIn(0f, 1f) to readTone,
            (edge + 0.02f).coerceIn(0f, 1f) to unreadTone,
            1f to unreadTone
        )
    )
    val downloadBorder = if (progress >= 1f) BorderStroke(1.5.dp, Color(0xFF7aa2f7))
        else if (progress > 0f) BorderStroke(1.dp, Color(0xFF7aa2f7).copy(alpha = 0.5f))
        else null

    Card(
        modifier = Modifier
            .padding(4.dp)
            .height(64.dp)
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(containerColor = Color.Transparent),
        border = downloadBorder,
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(fillBrush),
            contentAlignment = Alignment.Center
        ) {
            Text(
                book.name,
                textAlign = TextAlign.Center,
                style = MaterialTheme.typography.labelMedium
            )
        }
    }
}
