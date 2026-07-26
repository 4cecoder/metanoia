package com.bytecats.metanoia.ui.screens.settings

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.bytecats.metanoia.viewmodel.MainViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun UpdateSettingsPage(navController: NavController, viewModel: MainViewModel) {
    val settings = viewModel.settingsManager
    var nightlyEnabled by remember { mutableStateOf(settings.nightlyUpdatesEnabled) }
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
            appVersionCode = (
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) pInfo.longVersionCode
                else @Suppress("DEPRECATION") pInfo.versionCode.toLong()
            ).toString()
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
            SettingToggle(
                "Nightly / Experimental Updates",
                "Opt in to check GitHub for the latest master build. Sideload-only, may be unstable.",
                nightlyEnabled
            ) {
                nightlyEnabled = it
                settings.nightlyUpdatesEnabled = it
            }

            Text(
                "Current build: ${com.bytecats.metanoia.BuildConfig.GIT_COMMIT_SHA.take(7)}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.outline
            )
            Text(
                "App version: $appVersionName (build $appVersionCode)",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.outline
            )

            if (!nightlyEnabled) {
                Text(
                    "Enable to check for nightly builds",
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
                                com.bytecats.metanoia.update.UpdateChecker.fetchLatest()
                            }
                            settings.lastUpdateCheckMillis = System.currentTimeMillis()
                            val avail = com.bytecats.metanoia.update.UpdateChecker.isUpdateAvailable(
                                com.bytecats.metanoia.BuildConfig.GIT_COMMIT_SHA, result
                            )
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
                        "Update available (commit $shortSha, published ${updateInfo?.publishedAt ?: "unknown"})"
                    }
                    else -> "Up to date"
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
