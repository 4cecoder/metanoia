package com.bytecats.metanoia.ui.screens.settings

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Commit
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

data class ChangelogEntry(
    val sha: String,
    val summary: String,
    val category: String
)

object AppChangelog {
    val entries = listOf(
        ChangelogEntry("20f198a", "Add reference parsing (e.g. 1 John 3:16), SettingsManager bounds, BPE token cleaning", "Feature"),
        ChangelogEntry("c2a30ec", "Enable isIncludeAndroidResources in unitTests block for Compose Robolectric tests", "Build"),
        ChangelogEntry("0b77d0b", "Ensure BibleDatabase openDb defaults to writable mode for tests and DAOs", "Fix"),
        ChangelogEntry("a469441", "Update BookGridProgressTest unit tests for multi-canon progress map", "Test"),
        ChangelogEntry("176220d", "Optimize DAO queries, TTS audio resilience, StudySheet & LexiconSheet UI", "Optimization"),
        ChangelogEntry("e081f78", "Add VerseItem component enhancements and RTL support", "Feature"),
        ChangelogEntry("7753ff5", "Add comprehensive TDD unit test suites for analytics and book progress", "Test"),
        ChangelogEntry("1da9b3f", "Add path filters to CI workflows to bypass docs/markdown changes", "CI/CD"),
        ChangelogEntry("059877f", "Restore per-book progress bars and dynamic lerpColor gradient fill in dashboard", "Feature"),
        ChangelogEntry("ae5116f", "Add GitHub Pages developer portal with Tokyo Night theme and SPA router", "Web"),
        ChangelogEntry("3a2389b", "Restore MY READING analytics dashboard screen and stats calculation", "Feature")
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChangelogScreen(onBack: () -> Unit) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("CHANGELOG") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                }
            )
        }
    ) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .padding(innerPadding)
                .fillMaxSize()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            items(AppChangelog.entries) { entry ->
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f))
                ) {
                    Row(
                        modifier = Modifier.padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(16.dp)
                    ) {
                        Icon(Icons.Default.Commit, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                        Column(modifier = Modifier.weight(1f)) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(
                                    entry.sha,
                                    fontWeight = FontWeight.Bold,
                                    color = MaterialTheme.colorScheme.primary,
                                    style = MaterialTheme.typography.labelLarge
                                )
                                Surface(
                                    shape = MaterialTheme.shapes.small,
                                    color = MaterialTheme.colorScheme.primaryContainer
                                ) {
                                    Text(
                                        entry.category,
                                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onPrimaryContainer
                                    )
                                }
                            }
                            Spacer(modifier = Modifier.height(4.dp))
                            Text(entry.summary, style = MaterialTheme.typography.bodyMedium)
                        }
                    }
                }
            }
        }
    }
}
