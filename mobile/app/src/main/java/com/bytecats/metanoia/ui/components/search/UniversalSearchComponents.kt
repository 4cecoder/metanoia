package com.bytecats.metanoia.ui.components.search

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bytecats.metanoia.bible.UniversalBibleSearch
import com.bytecats.metanoia.models.BibleBook
import com.bytecats.metanoia.models.TextTradition
import com.bytecats.metanoia.models.Canon

/**
 * Search bar for universal Bible search.
 *
 * Searches ALL books across ALL canons with no filtering.
 * Nothing is hidden.
 */
@Composable
fun UniversalSearchBar(
    query: String,
    onQueryChange: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    OutlinedTextField(
        value = query,
        onValueChange = onQueryChange,
        placeholder = { Text("Search all books, canons, and traditions...") },
        leadingIcon = { Icon(Icons.Default.Search, contentDescription = "Search") },
        modifier = modifier.fillMaxWidth(),
        singleLine = true,
        shape = MaterialTheme.shapes.medium
    )
}

/**
 * Book card showing canon/tradition metadata.
 *
 * Makes visible what traditions include this book.
 * Prevents Protestant-centric hiding.
 */
@Composable
fun BookCard(
    book: BibleBook,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Card(
        onClick = onClick,
        modifier = modifier.fillMaxWidth(),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            // Book name and chapters
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    text = book.name,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = "${book.chapters} ch",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            Spacer(modifier = Modifier.height(8.dp))

            // Tradition badge
            TraditionBadge(book.textTradition)

            Spacer(modifier = Modifier.height(8.dp))

            // Canon badges
            CanonBadges(book.canons)

            Spacer(modifier = Modifier.height(8.dp))

            // Section
            Text(
                text = book.section.name.replace("([A-Z])".toRegex(), " $1").trim(),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

/**
 * Badge showing textual tradition.
 *
 * Makes clear which tradition the book belongs to:
 * - Masoretic (Hebrew)
 * - Septuagint (Greek)
 * - New Testament (Greek)
 * - Ethiopic (Ge'ez)
 */
@Composable
fun TraditionBadge(tradition: TextTradition) {
    val (label, color) = when (tradition) {
        TextTradition.Masoretic -> "Masoretic (Hebrew)" to Color(0xFF4CAF50)    // Green
        TextTradition.Septuagint -> "Septuagint (Greek)" to Color(0xFF2196F3)  // Blue
        TextTradition.NewTestament -> "New Testament" to Color(0xFF9C27B0)      // Purple
        TextTradition.Ethiopic -> "Ethiopic (Ge'ez)" to Color(0xFFFF9800)       // Orange
    }

    AssistChip(
        onClick = {},
        label = { Text(label, style = MaterialTheme.typography.labelSmall) },
        leadingIcon = {
            Icon(
                when (tradition) {
                    TextTradition.Masoretic -> Icons.Default.Language
                    TextTradition.Septuagint -> Icons.Default.Translate
                    TextTradition.NewTestament -> Icons.Default.Book
                    TextTradition.Ethiopic -> Icons.Default.AutoStories
                },
                contentDescription = null,
                modifier = Modifier.size(16.dp)
            )
        },
        colors = AssistChipDefaults.assistChipColors(
            containerColor = color.copy(alpha = 0.1f),
            labelColor = color
        )
    )
}

/**
 * Badges showing which canons include this book.
 *
 * Makes visible the canonical distribution.
 * Prevents hiding books that are only in some canons.
 */
@Composable
fun CanonBadges(canons: Set<Canon>) {
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Canon.Protestant.takeIf { it in canons }?.let {
            CanonBadge(it, Color(0xFF9E9E9E))  // Gray
        }
        Canon.Catholic.takeIf { it in canons }?.let {
            CanonBadge(it, Color(0xFFF44336))  // Red
        }
        Canon.Orthodox.takeIf { it in canons }?.let {
            CanonBadge(it, Color(0xFF3F51B5))  // Indigo
        }
        Canon.Ethiopian.takeIf { it in canons }?.let {
            CanonBadge(it, Color(0xFFFF9800))  // Orange
        }
    }
}

/**
 * Single canon badge.
 */
@Composable
fun CanonBadge(canon: Canon, color: Color) {
    SuggestionChip(
        onClick = {},
        label = { Text(canon.name, style = MaterialTheme.typography.labelSmall) },
        colors = SuggestionChipDefaults.suggestionChipColors(
            containerColor = color.copy(alpha = 0.1f),
            labelColor = color
        )
    )
}

/**
 * Search results list showing matching books.
 *
 * Displays ALL matching books with full metadata.
 * No canonical filtering.
 */
@Composable
fun SearchResultsList(
    books: List<BibleBook>,
    onBookClick: (BibleBook) -> Unit,
    modifier: Modifier = Modifier
) {
    LazyColumn(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        if (books.isEmpty()) {
            item {
                EmptySearchResults()
            }
        } else {
            items(books) { book ->
                BookCard(
                    book = book,
                    onClick = { onBookClick(book) }
                )
            }
        }
    }
}

/**
 * Empty state for no search results.
 */
@Composable
fun EmptySearchResults() {
    Column(
        modifier = Modifier.fillMaxWidth().padding(32.dp),
        horizontalAlignment = androidx.compose.ui.Alignment.CenterHorizontally
    ) {
        Icon(
            Icons.Default.SearchOff,
            contentDescription = null,
            modifier = Modifier.size(64.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(modifier = Modifier.height(16.dp))
        Text(
            text = "No books found",
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(
            text = "Try a different search term",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

/**
 * Statistics card showing corpus breakdown.
 *
 * Makes visible the full scope of the biblical corpus.
 * Counters Protestant-centric bias by showing what exists
 * beyond the 66-book canon.
 */
@Composable
fun CorpusStatisticsCard(
    totalBooks: Int,
    byTradition: Map<TextTradition, Int>,
    missingFromProtestant: Int,
    ethiopianExclusive: Int,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant
        )
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                text = "Biblical Corpus",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold
            )

            Spacer(modifier = Modifier.height(12.dp))

            // Total
            StatRow("Total Books", totalBooks.toString())

            Spacer(modifier = Modifier.height(8.dp))

            // By tradition
            Divider()
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "By Textual Tradition",
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Bold
            )
            Spacer(modifier = Modifier.height(8.dp))

            byTradition.forEach { (tradition, count) ->
                TraditionStatRow(tradition, count)
            }

            Spacer(modifier = Modifier.height(8.dp))

            // Missing from Protestant
            Divider()
            Spacer(modifier = Modifier.height(8.dp))
            StatRow(
                "Missing from Protestant",
                missingFromProtestant.toString(),
                highlight = true,
                note = "Books Protestant removed from Bibles"
            )

            // Ethiopian exclusive
            StatRow(
                "Ethiopian Exclusive",
                ethiopianExclusive.toString(),
                highlight = true,
                note = "Books only in Ethiopian canon"
            )
        }
    }
}

@Composable
fun StatRow(label: String, value: String, highlight: Boolean = false, note: String? = null) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Column {
            Text(
                text = label,
                style = if (highlight) {
                    MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold)
                } else {
                    MaterialTheme.typography.bodyMedium
                }
            )
            note?.let {
                Text(
                    text = it,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
        Text(
            text = value,
            style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Bold),
            color = if (highlight) {
                MaterialTheme.colorScheme.primary
            } else {
                MaterialTheme.colorScheme.onSurface
            }
        )
    }
}

@Composable
fun TraditionStatRow(tradition: TextTradition, count: Int) {
    val traditionName = when (tradition) {
        TextTradition.Masoretic -> "Masoretic (Hebrew)"
        TextTradition.Septuagint -> "Septuagint (Greek)"
        TextTradition.NewTestament -> "New Testament"
        TextTradition.Ethiopic -> "Ethiopic (Ge'ez)"
    }

    StatRow(traditionName, count.toString())
}