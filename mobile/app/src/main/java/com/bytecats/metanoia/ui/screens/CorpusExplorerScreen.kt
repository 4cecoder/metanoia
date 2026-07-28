package com.bytecats.metanoia.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bytecats.metanoia.bible.BibleManager
import com.bytecats.metanoia.bible.UniversalBibleSearch
import com.bytecats.metanoia.models.BibleBook
import com.bytecats.metanoia.models.TextTradition
import com.bytecats.metanoia.ui.components.search.*
import kotlinx.coroutines.launch

/**
 * Corpus Explorer Screen.
 *
 * Shows the COMPLETE biblical corpus organized by textual tradition:
 * - Masoretic (Hebrew OT)
 * - Septuagint (Greek OT + Deuterocanonical)
 * - New Testament (Greek)
 * - Ethiopic (Ge'ez)
 *
 * This screen exists to UN-bury what Protestantism hid.
 * Nothing is filtered. Everything is discoverable.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CorpusExplorerScreen(
    bibleManager: BibleManager,
    onBookClick: (BibleBook) -> Unit,
    onBackClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    var searchQuery by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()
    val universalSearch = remember { UniversalBibleSearch() }

    // Computed results
    val corpusStats = remember { universalSearch.getCorpusStatistics() }
    val allBooksByTradition = remember { universalSearch.getAllBooksByTradition() }
    val septuagintOnly = remember { universalSearch.getSeptuagintOnlyBooks() }
    val ethiopicOnly = remember { universalSearch.getEthiopicOnlyBooks() }
    val universalBooks = remember { universalSearch.getUniversalBooks() }
    val missingFromProtestant = remember { universalSearch.getMissingFromProtestant() }

    // Search results (empty when no query)
    val searchResults = remember(searchQuery) {
        if (searchQuery.isBlank()) emptyList()
        else universalSearch.searchBooks(searchQuery)
    }

    // Selected tab
    var selectedTab by remember { mutableStateOf(CorpusTab.CORPUS) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Corpus Explorer") },
                navigationIcon = {
                    IconButton(onClick = onBackClick) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                    }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = modifier
                .fillMaxSize()
                .padding(padding)
        ) {
            // Search bar (always visible)
            UniversalSearchBar(
                query = searchQuery,
                onQueryChange = { searchQuery = it },
                modifier = Modifier.padding(16.dp)
            )

            Spacer(modifier = Modifier.height(8.dp))

            // Tab row
            TabRow(selectedTabIndex = selectedTab.ordinal) {
                CorpusTab.values().forEach { tab ->
                    Tab(
                        selected = selectedTab == tab,
                        onClick = { selectedTab = tab },
                        text = { Text(tab.label) }
                    )
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Content based on selected tab
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                when (selectedTab) {
                    CorpusTab.CORPUS -> {
                        item {
                            CorpusOverviewContent(
                                corpusStats = corpusStats,
                                allBooksByTradition = allBooksByTradition,
                                onBookClick = onBookClick
                            )
                        }
                    }
                    CorpusTab.SEPTUAGINT -> {
                        item {
                            TraditionSection(
                                tradition = TextTradition.Septuagint,
                                books = allBooksByTradition[TextTradition.Septuagint] ?: emptyList(),
                                onBookClick = onBookClick,
                                description = "Greek Old Testament (Septuagint). Includes deuterocanonical books that Protestantism removed."
                            )
                        }
                    }
                    CorpusTab.ETHIOPIC -> {
                        item {
                            TraditionSection(
                                tradition = TextTradition.Ethiopic,
                                books = allBooksByTradition[TextTradition.Ethiopic] ?: emptyList(),
                                onBookClick = onBookClick,
                                description = "Ethiopic (Ge'ez) texts. Books unique to Ethiopian Orthodox canon, completely unknown to Western readers."
                            )
                        }
                    }
                    CorpusTab.MISSING -> {
                        item {
                            MissingBooksSection(
                                missingBooks = missingFromProtestant,
                                onBookClick = onBookClick
                            )
                        }
                    }
                    CorpusTab.SEARCH -> {
                        if (searchResults.isEmpty()) {
                            item {
                                EmptySearchResults()
                            }
                        } else {
                            items(searchResults) { book ->
                                BookCard(
                                    book = book,
                                    onClick = { onBookClick(book) }
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

/**
 * Corpus overview with statistics.
 */
@Composable
fun CorpusOverviewContent(
    corpusStats: com.bytecats.metanoia.bible.CorpusStatistics,
    allBooksByTradition: Map<TextTradition, List<BibleBook>>,
    onBookClick: (BibleBook) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        // Statistics card
        CorpusStatisticsCard(
            totalBooks = corpusStats.totalBooks,
            byTradition = corpusStats.byTradition,
            missingFromProtestant = corpusStats.missingFromProtestant,
            ethiopianExclusive = corpusStats.ethiopianExclusive
        )

        // Masoretic (Hebrew) section
        allBooksByTradition[TextTradition.Masoretic]?.let { books ->
            TraditionSection(
                tradition = TextTradition.Masoretic,
                books = books,
                onBookClick = onBookClick,
                description = "Hebrew Old Testament (Masoretic). The 39 books of the Protestant Old Testament in their original Hebrew."
            )
        }

        // Septuagint (Greek) section
        allBooksByTradition[TextTradition.Septuagint]?.let { books ->
            TraditionSection(
                tradition = TextTradition.Septuagint,
                books = books,
                onBookClick = onBookClick,
                description = "Greek Old Testament (Septuagint). The LXX includes deuterocanonical books that Catholic and Orthodox churches accept but Protestantism rejected."
            )
        }

        // New Testament section
        allBooksByTradition[TextTradition.NewTestament]?.let { books ->
            TraditionSection(
                tradition = TextTradition.NewTestament,
                books = books,
                onBookClick = onBookClick,
                description = "Greek New Testament. 27 books, same across all Christian traditions."
            )
        }

        // Ethiopic section
        allBooksByTradition[TextTradition.Ethiopic]?.let { books ->
            TraditionSection(
                tradition = TextTradition.Ethiopic,
                books = books,
                onBookClick = onBookClick,
                description = "Ethiopic (Ge'ez) texts. Unique to Ethiopian Orthodox canon, including Enoch and Jubilees."
            )
        }
    }
}

/**
 * Section for books by tradition.
 */
@Composable
fun TraditionSection(
    tradition: TextTradition,
    books: List<BibleBook>,
    onBookClick: (BibleBook) -> Unit,
    description: String
) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        // Tradition header
        Row(verticalAlignment = Alignment.CenterVertically) {
            TraditionBadge(tradition)
            Spacer(modifier = Modifier.width(12.dp))
            Column {
                Text(
                    text = when (tradition) {
                        TextTradition.Masoretic -> "Masoretic (Hebrew)"
                        TextTradition.Septuagint -> "Septuagint (Greek)"
                        TextTradition.NewTestament -> "New Testament (Greek)"
                        TextTradition.Ethiopic -> "Ethiopic (Ge'ez)"
                    },
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = "${books.size} books",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        // Description
        Text(
            text = description,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        // Book cards
        books.forEach { book ->
            BookCard(
                book = book,
                onClick = { onBookClick(book) }
            )
        }
    }
}

/**
 * Section for books missing from Protestant canon.
 *
 * This exists to REVEAL what Protestantism HID.
 */
@Composable
fun MissingBooksSection(
    missingBooks: List<BibleBook>,
    onBookClick: (BibleBook) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        // Header
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                Icons.Default.VisibilityOff,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.error
            )
            Spacer(modifier = Modifier.width(12.dp))
            Column {
                Text(
                    text = "Books Missing from Protestant Canon",
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.error
                )
                Text(
                    text = "${missingBooks.size} books removed by Protestant Reformation",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        Spacer(modifier = Modifier.height(8.dp))

        // Explanation
        Text(
            text = "These books were included in Bibles for over 1,500 years until the Protestant Reformation removed them. Catholic and Orthodox churches continue to use them, and Ethiopian canon includes even more.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        Spacer(modifier = Modifier.height(16.dp))

        // Deuterocanonical (Catholic/Orthodox)
        val deuterocanonical = missingBooks.filter {
            com.bytecats.metanoia.models.Canon.Catholic in it.canons ||
            com.bytecats.metanoia.models.Canon.Orthodox in it.canons
        }

        if (deuterocanonical.isNotEmpty()) {
            Text(
                text = "Deuterocanonical (Catholic & Orthodox)",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold
            )
            Spacer(modifier = Modifier.height(8.dp))
            deuterocanonical.forEach { book ->
                BookCard(
                    book = book,
                    onClick = { onBookClick(book) }
                )
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Ethiopian exclusive
        val ethiopianExclusive = missingBooks.filter {
            com.bytecats.metanoia.models.Canon.Ethiopian in it.canons &&
            com.bytecats.metanoia.models.Canon.Catholic !in it.canons &&
            com.bytecats.metanoia.models.Canon.Orthodox !in it.canons
        }

        if (ethiopianExclusive.isNotEmpty()) {
            Text(
                text = "Ethiopian Exclusive",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold
            )
            Spacer(modifier = Modifier.height(8.dp))
            ethiopianExclusive.forEach { book ->
                BookCard(
                    book = book,
                    onClick = { onBookClick(book) }
                )
            }
        }
    }
}

/**
 * Tabs for corpus explorer.
 */
enum class CorpusTab(val label: String) {
    CORPUS("Corpus"),
    SEPTUAGINT("LXX Greek"),
    ETHIOPIC("Ethiopic"),
    MISSING("Missing"),
    SEARCH("Search")
}