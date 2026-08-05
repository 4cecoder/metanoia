package com.bytecats.metanoia.ui.screens.settings

import androidx.compose.foundation.BorderStroke
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

data class TimelineMilestone(
    val date: String,
    val title: String,
    val highlights: List<String>,
    val commitCount: Int
)

object AppTimeline {
    val milestones = listOf(
        TimelineMilestone(
            date = "2026-08-05",
            title = "Cyberpunk Metrics, Hebrew RTL & Download Feedback",
            highlights = listOf(
                "Added cyberpunk-style chapter word count badges & top bar book stats",
                "Enforced Hebrew Right-to-Left (RTL) text orientation for lexicon lemmas",
                "Added book long-press action modal with full book download automation",
                "Restored interactive lerpColor progress gradient on book grid cards",
                "Built GitHub Pages web portal with Tokyo Night glassmorphism & SPA router",
                "Added comprehensive TDD unit test suites for analytics, TTS, and DAOs"
            ),
            commitCount = 14
        ),
        TimelineMilestone(
            date = "2026-07-15",
            title = "Cross-Platform Hardening & Developer Portal",
            highlights = listOf(
                "Cross-platform audio playback + MSYS2 setup hardening for Windows",
                "Extracted type-safe signal layer and UI kit into src/kit/",
                "Organized documentation & subagent task workflows"
            ),
            commitCount = 5
        ),
        TimelineMilestone(
            date = "2026-06-23",
            title = "Tokyo Night GTK4 Architecture & Modular Refactoring",
            highlights = listOf(
                "Refactored BibleDatabase, BibleScraper, and TTSAudioPlayer",
                "Applied Tokyo Night theme for GTK4 dropdown popovers & sidebar",
                "Resolved mobile app rebase merge conflicts & modularized components"
            ),
            commitCount = 7
        ),
        TimelineMilestone(
            date = "2026-06-10",
            title = "AI VM Gateway Integration",
            highlights = listOf(
                "Wired up AI VM gateway endpoints & remote gateway settings page",
                "Enabled remote TTS engine streaming & configuration"
            ),
            commitCount = 1
        ),
        TimelineMilestone(
            date = "2026-03-05",
            title = "Professional Mobile Studio & Remote TTS",
            highlights = listOf(
                "Modular component-based architecture & dynamic voice engine",
                "GTK4 compatibility fixes for desktop app"
            ),
            commitCount = 3
        ),
        TimelineMilestone(
            date = "2026-03-01",
            title = "Metanoia Genesis: Autonomous Qwen3-TTS CUDA Engine",
            highlights = listOf(
                "Autonomous CUDA and system dependency provisioning for RTX 4090",
                "Implemented multi-tier caching (Prompt & Tensor) for 10x TTS speedup",
                "Added WSL Mission Control status dashboard & remote voice upload API",
                "Initial repository creation and foundational architecture"
            ),
            commitCount = 42
        )
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChangelogScreen(onBack: () -> Unit) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("DEVELOPMENT TIMELINE") },
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
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            items(AppTimeline.milestones) { milestone ->
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f)),
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f))
                ) {
                    Column(modifier = Modifier.padding(18.dp)) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Icon(Icons.Default.Commit, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                                Text(milestone.date, fontWeight = FontWeight.Bold, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
                            }
                            Surface(
                                shape = MaterialTheme.shapes.small,
                                color = MaterialTheme.colorScheme.secondaryContainer
                            ) {
                                Text(
                                    "${milestone.commitCount} commits",
                                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSecondaryContainer
                                )
                            }
                        }
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(milestone.title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Black)
                        Spacer(modifier = Modifier.height(10.dp))
                        milestone.highlights.forEach { highlight ->
                            Row(modifier = Modifier.padding(vertical = 2.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text("•", color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.Bold)
                                Text(highlight, style = MaterialTheme.typography.bodyMedium)
                            }
                        }
                    }
                }
            }
        }
    }
}
