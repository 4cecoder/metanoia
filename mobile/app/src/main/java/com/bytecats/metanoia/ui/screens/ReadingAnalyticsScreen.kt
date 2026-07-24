package com.bytecats.metanoia.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.bytecats.metanoia.bible.BibleManager
import com.bytecats.metanoia.bible.ReadingStats
import com.bytecats.metanoia.models.BOOKS
import com.bytecats.metanoia.ui.components.StatItemCompact

/**
 * "MY READING" -- usage/reading-behavior analytics: most-read books,
 * weekly/monthly/yearly activity, longevity, and overall read-vs-total
 * chapter completion. Deliberately separate from LibraryStatsScreen
 * ("LIBRARY ANALYTICS"), which is only about downloaded-content size/counts
 * and stays untouched -- see that file's header comment.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReadingAnalyticsScreen(navController: NavController, bible: BibleManager) {
    val mostRead = remember { bible.getMostReadBooks(5) }
    val now = remember { System.currentTimeMillis() }
    val weekCount = remember { bible.getReadingEventCounts(ReadingStats.weekCutoff(now)) }
    val monthCount = remember { bible.getReadingEventCounts(ReadingStats.monthCutoff(now)) }
    val yearCount = remember { bible.getReadingEventCounts(ReadingStats.yearCutoff(now)) }
    val firstRead = remember { bible.getFirstEverReadTimestamp() }
    val daysReading = remember { firstRead?.let { ReadingStats.daysSince(it, now) } }

    // Overall read-vs-total completion, reusing getReadCompletion() (per-book
    // fraction) rather than a new dedicated aggregate DB method -- reconstruct
    // each book's read-chapter count from its fraction * its total chapters.
    val readCompletion = remember { bible.getReadCompletion() }
    val totalChapters = remember { BOOKS.sumOf { it.chapters } }
    val readChapters = remember {
        readCompletion.entries.sumOf { (name, frac) ->
            val total = BOOKS.find { it.name == name }?.chapters ?: 0
            (frac * total).toInt()
        }
    }
    val overallFraction = if (totalChapters > 0) readChapters.toFloat() / totalChapters else 0f
    // Reuses the same pure interpolation the book-card read gradient uses
    // (ReadingStats.lerpColor), from the theme's neutral outline tone up to
    // the existing Tokyo Night "read" green (#9ece6a) -- not a new color.
    val neutralArgb = MaterialTheme.colorScheme.outline.toArgb() and 0xFFFFFF
    val completionColor = Color(
        ReadingStats.lerpColor(neutralArgb, 0x9ece6a, overallFraction) or (0xFF shl 24)
    )

    Scaffold(topBar = {
        TopAppBar(
            title = { Text("MY READING") },
            navigationIcon = {
                IconButton(onClick = { navController.popBackStack() }) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                }
            }
        )
    }) { innerPadding ->
        Column(modifier = Modifier.padding(innerPadding).fillMaxSize().padding(24.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(20.dp)) {
            Text("READING HABITS", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)

            Card(modifier = Modifier.fillMaxWidth(), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.2f))) {
                Column(modifier = Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        StatItemCompact("This Week", "$weekCount")
                        StatItemCompact("This Month", "$monthCount")
                        StatItemCompact("This Year", "$yearCount")
                    }
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                        Text("Reading with Metanoia for", fontWeight = FontWeight.Bold)
                        Text(
                            daysReading?.let { "$it day${if (it == 1) "" else "s"}" } ?: "Not yet started",
                            color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.Black
                        )
                    }
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                        Text("Bible Read", fontWeight = FontWeight.Bold)
                        Text("%.1f%%".format(overallFraction * 100), color = completionColor, fontWeight = FontWeight.Black)
                    }
                }
            }

            Text("MOST READ", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
            Card(modifier = Modifier.fillMaxWidth(), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.2f))) {
                if (mostRead.isEmpty()) {
                    Text(
                        "Nothing read yet -- open a chapter to start tracking.",
                        modifier = Modifier.padding(24.dp),
                        color = MaterialTheme.colorScheme.outline
                    )
                } else {
                    Column(modifier = Modifier.padding(vertical = 8.dp)) {
                        mostRead.forEachIndexed { idx, (book, count) ->
                            Row(
                                modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 10.dp),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Text(
                                        "${idx + 1}",
                                        modifier = Modifier.width(24.dp),
                                        color = MaterialTheme.colorScheme.outline,
                                        fontWeight = FontWeight.Bold
                                    )
                                    Text(book, fontWeight = FontWeight.Bold)
                                }
                                Text("$count view${if (count == 1) "" else "s"}", color = MaterialTheme.colorScheme.primary)
                            }
                            if (idx < mostRead.lastIndex) HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f))
                        }
                    }
                }
            }
            Spacer(modifier = Modifier.height(8.dp))
        }
    }
}
