package com.bytecats.metanoia.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.DeleteForever
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.bytecats.metanoia.bible.ReadingStats
import com.bytecats.metanoia.bible.VerseReference
import com.bytecats.metanoia.models.BOOKS
import com.bytecats.metanoia.ui.components.ConfirmActionDialog
import com.bytecats.metanoia.ui.components.StatItemCompact
import com.bytecats.metanoia.viewmodel.MainViewModel
import java.time.LocalDate
import java.time.format.TextStyle
import java.util.Locale

// Tokyo Night palette shared with BibleScreen.kt -- reused, not reinvented.
private val TokyoGreen = Color(0xFF9ece6a)
private val TokyoBlue = Color(0xFF7aa2f7)
private val TokyoAmber = Color(0xFFe0af68)

/**
 * "MY READING" -- usage/reading-behavior analytics: streaks, a 14-day
 * activity chart, day-of-week/time-of-day habits, testament coverage,
 * most-read books, weekly/monthly/yearly activity, longevity, and overall
 * read-vs-total chapter completion. Deliberately separate from
 * LibraryStatsScreen ("LIBRARY ANALYTICS"), which is only about
 * downloaded-content size/counts and stays untouched -- see that file's
 * header comment.
 *
 * Takes the full MainViewModel (rather than just BibleManager, as before)
 * so it can read settings.showEthiopianCanon for the testament breakdown --
 * same dependency shape BibleScreen.kt uses for the same toggle.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReadingAnalyticsScreen(navController: NavController, viewModel: MainViewModel) {
    val bible = viewModel.bibleManager
    val settings = viewModel.settingsManager

    // Bumped after a reset to force every remember() below keyed on it to
    // recompute from the now-empty tables, without needing per-field mutable
    // state plumbing for each stat.
    var resetNonce by remember { mutableIntStateOf(0) }
    var showResetDialog by remember { mutableStateOf(false) }

    val mostRead = remember(resetNonce) { bible.getMostReadBooks(5) }
    val hotChapters = remember(resetNonce) { bible.getHotChapters(10) }
    val now = remember(resetNonce) { System.currentTimeMillis() }
    val weekCount = remember(resetNonce) { bible.getReadingEventCounts(ReadingStats.weekCutoff(now)) }
    val monthCount = remember(resetNonce) { bible.getReadingEventCounts(ReadingStats.monthCutoff(now)) }
    val yearCount = remember(resetNonce) { bible.getReadingEventCounts(ReadingStats.yearCutoff(now)) }
    val firstRead = remember(resetNonce) { bible.getFirstEverReadTimestamp() }
    val daysReading = remember(resetNonce) { firstRead?.let { ReadingStats.daysSince(it, now) } }

    // Overall read-vs-total completion, reusing getReadCompletion() (per-book
    // fraction) rather than a new dedicated aggregate DB method -- reconstruct
    // each book's read-chapter count from its fraction * its total chapters.
    val readCompletion = remember(resetNonce) { bible.getReadCompletion() }
    val totalChapters = remember { BOOKS.sumOf { it.chapters } }
    val readChapters = remember(readCompletion) {
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

    // --- Streaks ---
    val readEpochDays = remember(resetNonce) { bible.getReadEpochDaysDescending() }
    val todayEpochDay = remember { LocalDate.now().toEpochDay() }
    val currentStreak = remember(readEpochDays) { ReadingStats.currentStreak(readEpochDays, todayEpochDay) }
    val longestStreak = remember(readEpochDays) { ReadingStats.longestStreak(readEpochDays) }

    // --- Activity chart (last 14 days) ---
    val dailyCounts = remember(resetNonce) { bible.getDailyReadCounts(14) }

    // --- Habits ---
    val dayOfWeekCounts = remember(resetNonce) { bible.getDayOfWeekCounts() }
    val hourCounts = remember(resetNonce) { bible.getHourOfDayCounts() }
    val mostActiveDayIdx = remember(dayOfWeekCounts) { ReadingStats.mostActiveDayOfWeek(dayOfWeekCounts) }
    val mostActiveTime = remember(hourCounts) { ReadingStats.mostActiveTimeOfDay(hourCounts) }
    val dayOfWeekNames = listOf("Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday")

    // --- Testament breakdown ---
    val testamentCounts = remember(resetNonce) { bible.getTestamentReadCounts() }
    val testamentTotals = remember {
        listOf("Old", "New", "Eth").associateWith { key -> BOOKS.filter { it.testament == key }.sumOf { it.chapters } }
    }

    Scaffold(topBar = {
        TopAppBar(
            title = { Text("MY READING") },
            navigationIcon = {
                IconButton(onClick = { navController.popBackStack() }) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                }
            },
            actions = {
                IconButton(onClick = { showResetDialog = true }) {
                    Icon(Icons.Default.DeleteForever, contentDescription = "Reset reading history")
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

            Text("STREAK", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
            Card(modifier = Modifier.fillMaxWidth(), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.2f))) {
                if (currentStreak == 0 && longestStreak == 0) {
                    Text(
                        "Start reading today to begin a streak.",
                        modifier = Modifier.padding(24.dp),
                        color = MaterialTheme.colorScheme.outline
                    )
                } else {
                    Row(modifier = Modifier.fillMaxWidth().padding(24.dp), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Default.LocalFireDepartment, contentDescription = null, tint = TokyoAmber)
                            Spacer(modifier = Modifier.width(4.dp))
                            StatItemCompact("Current Streak", "$currentStreak day${if (currentStreak == 1) "" else "s"}")
                        }
                        StatItemCompact("Longest Streak", "$longestStreak day${if (longestStreak == 1) "" else "s"}")
                    }
                }
            }

            Text("LAST 14 DAYS", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
            Card(modifier = Modifier.fillMaxWidth(), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.2f))) {
                Column(modifier = Modifier.padding(24.dp).fillMaxWidth()) {
                    ActivityBarChart(dailyCounts, todayEpochDay)
                }
            }

            Text("HABITS", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
            Card(modifier = Modifier.fillMaxWidth(), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.2f))) {
                if (mostActiveDayIdx == null) {
                    Text(
                        "Not enough data yet -- keep reading to see your habits.",
                        modifier = Modifier.padding(24.dp),
                        color = MaterialTheme.colorScheme.outline
                    )
                } else {
                    Column(modifier = Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                            Text("Most Active Day", fontWeight = FontWeight.Bold)
                            Text(dayOfWeekNames[mostActiveDayIdx], color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.Black)
                        }
                        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                            Text("Most Active Time", fontWeight = FontWeight.Bold)
                            Text(mostActiveTime, color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.Black)
                        }
                    }
                }
            }

            Text("SCRIPTURE COVERAGE", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
            Card(modifier = Modifier.fillMaxWidth(), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.2f))) {
                Column(modifier = Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    TestamentRow("Old Testament", testamentCounts["Old"] ?: 0, testamentTotals["Old"] ?: 0, TokyoGreen)
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                    TestamentRow("New Testament", testamentCounts["New"] ?: 0, testamentTotals["New"] ?: 0, TokyoBlue)
                    // Hidden when the user has switched off the Ethiopian
                    // canon, matching BibleScreen's book-picker filtering --
                    // this only hides the row, it doesn't touch any data.
                    if (settings.showEthiopianCanon) {
                        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                        TestamentRow("Ethiopian Canon", testamentCounts["Eth"] ?: 0, testamentTotals["Eth"] ?: 0, TokyoAmber)
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
                        mostRead.forEachIndexed { idx, entry ->
                            val book = entry.first
                            val count = entry.second
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
                            if (idx < mostRead.size - 1) HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f))
                        }
                    }
                }
            }
            Text("HOT CHAPTERS", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
            Card(modifier = Modifier.fillMaxWidth(), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.2f))) {
                if (hotChapters.isEmpty()) {
                    Text(
                        "Nothing read yet -- open a chapter to start tracking.",
                        modifier = Modifier.padding(24.dp),
                        color = MaterialTheme.colorScheme.outline
                    )
                } else {
                    Column(modifier = Modifier.padding(vertical = 8.dp)) {
                        hotChapters.forEachIndexed { idx, hot ->
                            val verseRef = VerseReference(hot.book, hot.chapter, null)
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable {
                                        viewModel.pendingDeepLink = verseRef
                                        navController.navigate("bible")
                                    }
                                    .padding(horizontal = 24.dp, vertical = 10.dp),
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
                                    Text("${hot.book} ${hot.chapter}", fontWeight = FontWeight.Bold)
                                }
                                Text("${hot.views} view${if (hot.views == 1) "" else "s"}", color = TokyoAmber)
                            }
                            if (idx < hotChapters.lastIndex) HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f))
                        }
                    }
                }
            }
            Spacer(modifier = Modifier.height(8.dp))
        }
    }

    if (showResetDialog) {
        ConfirmActionDialog(
            title = "Reset Reading History?",
            msg = "This clears your reading streaks and history. Downloaded chapter text is not affected. This can't be undone.",
            onConfirm = {
                bible.clearReadingHistory()
                resetNonce++
            },
            onDismiss = { showResetDialog = false }
        )
    }
}

/**
 * Hand-rolled bar chart -- a Row of weighted Boxes, each one's height set via
 * fillMaxHeight(fraction) rather than any chart library. `todayEpochDay` is
 * highlighted in blue; every other day is green, dimmed when its count is 0
 * so an empty day still renders as a visible baseline rather than vanishing.
 */
@Composable
private fun ActivityBarChart(data: List<Pair<Long, Int>>, todayEpochDay: Long) {
    val maxCount = (data.maxOfOrNull { it.second } ?: 0).coerceAtLeast(1)
    Row(
        modifier = Modifier.fillMaxWidth().height(120.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.Bottom
    ) {
        data.forEach { (day, count) ->
            val isToday = day == todayEpochDay
            val fraction = (count.toFloat() / maxCount).coerceIn(0.04f, 1f)
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxHeight(fraction)
                    .background(
                        if (isToday) TokyoBlue else TokyoGreen.copy(alpha = if (count > 0) 0.75f else 0.25f),
                        RoundedCornerShape(3.dp)
                    )
            )
        }
    }
    Spacer(modifier = Modifier.height(6.dp))
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        data.forEach { (day, _) ->
            val isToday = day == todayEpochDay
            val label = LocalDate.ofEpochDay(day).dayOfWeek.getDisplayName(TextStyle.NARROW, Locale.getDefault())
            Text(
                label,
                modifier = Modifier.weight(1f),
                textAlign = TextAlign.Center,
                style = MaterialTheme.typography.labelSmall,
                fontWeight = if (isToday) FontWeight.Black else FontWeight.Normal,
                color = if (isToday) TokyoBlue else MaterialTheme.colorScheme.outline
            )
        }
    }
}

@Composable
private fun TestamentRow(label: String, readChapters: Int, totalChapters: Int, accent: Color) {
    val fraction = if (totalChapters > 0) readChapters.toFloat() / totalChapters else 0f
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Text(label, fontWeight = FontWeight.Bold)
            Text(
                "$readChapters / $totalChapters chapters (%.0f%%)".format(fraction * 100),
                color = accent, fontWeight = FontWeight.Black, style = MaterialTheme.typography.labelMedium
            )
        }
        Box(modifier = Modifier.fillMaxWidth().height(8.dp).background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f), RoundedCornerShape(4.dp))) {
            Box(
                modifier = Modifier
                    .fillMaxHeight()
                    .fillMaxWidth(fraction.coerceIn(0f, 1f))
                    .background(accent.copy(alpha = 0.8f), RoundedCornerShape(4.dp))
            )
        }
    }
}
