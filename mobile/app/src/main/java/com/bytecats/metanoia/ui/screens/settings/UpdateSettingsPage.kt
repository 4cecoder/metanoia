package com.bytecats.metanoia.ui.screens.settings

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.bytecats.metanoia.BuildConfig
import com.bytecats.metanoia.viewmodel.MainViewModel
import com.bytecats.metanoia.update.ReleaseChannel
import com.bytecats.metanoia.update.UpdateChecker
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun UpdateSettingsPage(navController: NavController, viewModel: MainViewModel) {
    val settings = viewModel.settingsManager
    var releaseChannel by remember { mutableStateOf(settings.releaseChannel) }
    var updatesEnabled by remember { mutableStateOf(settings.updatesEnabled) }
    var isChecking by remember { mutableStateOf(false) }
    var hasChecked by remember { mutableStateOf(false) }
    val updateInfo = viewModel.availableUpdate.value
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    val context = androidx.compose.ui.platform.LocalContext.current
    var isDownloading by remember { mutableStateOf(false) }
    var downloadFailed by remember { mutableStateOf(false) }

    var appVersionName by remember { mutableStateOf("-") }
    var appVersionCode by remember { mutableStateOf("-") }
    LaunchedEffect(Unit) {
        try {
            val pInfo = context.packageManager.getPackageInfo(context.packageName, 0)
            appVersionName = pInfo.versionName ?: "-"
            appVersionCode = pInfo.longVersionCode.toString()
        } catch (e: Exception) {
            appVersionName = "-"
            appVersionCode = "-"
        }
    }

    Scaffold(topBar = {
        TopAppBar(
            title = { Text("UPDATES") },
            navigationIcon = {
                IconButton(onClick = { navController.popBackStack() }) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                }
            }
        )
    }) { innerPadding ->
        Column(
            modifier = Modifier.padding(innerPadding).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp)
        ) {
            // Update Channel Selection
            SettingSection("Release Channel") {
                SettingDropdown(
                    label = "Release Channel",
                    description = "Choose which release channel to receive updates from",
                    options = ReleaseChannel.values().toList(),
                    selectedOption = releaseChannel,
                    optionLabel = { it.displayName },
                    onOptionSelected = {
                        releaseChannel = it
                        settings.releaseChannel = it
                        // If switching to nightly, enable updates automatically
                        if (it == ReleaseChannel.NIGHTLY) {
                            updatesEnabled = true
                            settings.updatesEnabled = true
                        }
                        hasChecked = false // Reset check state when channel changes
                    }
                )

                Spacer(modifier = Modifier.height(12.dp))

                // Channel descriptions
                ChannelDescriptionCard(releaseChannel)
            }

            HorizontalDivider()

            // Enable Updates Toggle
            SettingToggle(
                "Check for Updates",
                "Automatically check for new releases on the selected channel",
                updatesEnabled
            ) {
                updatesEnabled = it
                settings.updatesEnabled = it
            }

            // Build Information
            Text(
                "Current build: ${BuildConfig.GIT_COMMIT_SHA.take(7)}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.outline
            )
            Text(
                "App version: $appVersionName (build $appVersionCode)",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.outline
            )

            if (!updatesEnabled) {
                Text(
                    "Enable updates to check for new releases",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.outline
                )
            } else {
                HorizontalDivider()

                Button(
                    onClick = {
                        isChecking = true
                        scope.launch {
                            val result = withContext(Dispatchers.IO) {
                                UpdateChecker.fetchLatestForChannel(releaseChannel)
                            }
                            settings.lastUpdateCheckMillis = System.currentTimeMillis()
                            val avail = UpdateChecker.isUpdateAvailable(
                                BuildConfig.GIT_COMMIT_SHA, result
                            )
                            if (result != null) {
                                settings.lastCheckedVersion = result.version
                            }
                            viewModel.availableUpdate.value = if (result != null && avail) result else null
                            hasChecked = true
                            isChecking = false
                        }
                    },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !isChecking
                ) {
                    if (isChecking) {
                        CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                    } else {
                        Icon(Icons.Default.SystemUpdate, null, modifier = Modifier.size(20.dp))
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("Check Now")
                    }
                }

                val updateAvailable = updateInfo != null
                val statusText = when {
                    !hasChecked && !updateAvailable -> "Not checked yet this session"
                    updateAvailable -> {
                        val shortSha = updateInfo?.commitSha?.take(7) ?: "unknown"
                        "Update available: ${updateInfo?.tagName ?: "unknown"} (commit $shortSha, published ${updateInfo?.publishedAt ?: "unknown"})"
                    }
                    else -> "Up to date on ${releaseChannel.displayName.lowercase()} channel"
                }
                Text(
                    statusText,
                    style = MaterialTheme.typography.bodySmall,
                    color = if (updateAvailable) MaterialTheme.colorScheme.primary
                            else MaterialTheme.colorScheme.outline
                )

                if (updateAvailable) {
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        if (updateInfo?.downloadUrl != null) {
                            Button(
                                onClick = {
                                    val url = updateInfo.downloadUrl ?: return@Button
                                    downloadFailed = false
                                    isDownloading = true
                                    scope.launch {
                                        val apk = withContext(Dispatchers.IO) {
                                            com.bytecats.metanoia.update.ApkInstaller.download(context, url)
                                        }
                                        isDownloading = false
                                        if (apk != null) {
                                            com.bytecats.metanoia.update.ApkInstaller.install(context, apk)
                                        } else {
                                            downloadFailed = true
                                        }
                                    }
                                },
                                modifier = Modifier.weight(1f),
                                enabled = !isDownloading
                            ) {
                                if (isDownloading) {
                                    CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                                } else {
                                    Icon(Icons.Default.Download, null, modifier = Modifier.size(20.dp))
                                }
                                Spacer(modifier = Modifier.width(8.dp))
                                Text(if (isDownloading) "Downloading..." else "Download & Install")
                            }
                        }
                        OutlinedButton(
                            onClick = { viewModel.dismissAvailableUpdate() },
                            modifier = Modifier.weight(1f),
                            enabled = !isDownloading
                        ) {
                            Text("Dismiss")
                        }
                    }
                    if (downloadFailed) {
                        Text(
                            "Download failed — check your connection and try again.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.error
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ChannelDescriptionCard(channel: ReleaseChannel) {
    val (title, description, icon, color) = when (channel) {
        ReleaseChannel.STABLE -> listOf(
            "Stable Channel",
            "Production-ready releases. Thoroughly tested and recommended for most users.",
            Icons.Default.CheckCircle,
            MaterialTheme.colorScheme.primary
        )
        ReleaseChannel.BETA -> listOf(
            "Beta Channel",
            "Testing releases with new features. May have bugs but receives regular testing.",
            Icons.Default.Science,
            MaterialTheme.colorScheme.tertiary
        )
        ReleaseChannel.ALPHA -> listOf(
            "Alpha Channel",
            "Early builds with the latest changes. May be unstable and is for developers only.",
            Icons.Default.BugReport,
            MaterialTheme.colorScheme.error
        )
        ReleaseChannel.NIGHTLY -> listOf(
            "Nightly Channel",
            "Latest master builds from the rolling \"latest\" tag. May be very unstable.",
            Icons.Default.Flare,
            MaterialTheme.colorScheme.secondary
        )
    }

    Card(
        colors = CardDefaults.cardColors(
            containerColor = color.copy(alpha = 0.1f)
        ),
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                icon,
                contentDescription = null,
                tint = color,
                modifier = Modifier.size(24.dp)
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    title,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Medium
                )
                Text(
                    description,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f)
                )
            }
        }
    }
}