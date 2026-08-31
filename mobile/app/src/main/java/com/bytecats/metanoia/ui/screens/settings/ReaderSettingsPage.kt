package com.bytecats.metanoia.ui.screens.settings

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.bytecats.metanoia.settings.SettingsManager

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReaderSettingsPage(navController: NavController, settings: SettingsManager) {
    var engSize by remember { mutableStateOf(settings.englishFontSize.toFloat()) }
    var ancSize by remember { mutableStateOf(settings.ancientFontSize.toFloat()) }
    var showEthiopian by remember { mutableStateOf(settings.showEthiopianCanon) }
    var showApocrypha by remember { mutableStateOf(settings.showApocrypha) }
    var useMasoretic by remember { mutableStateOf(settings.otTextTradition == "masoretic") }
    Scaffold(topBar = {
        TopAppBar(
            title = { Text("READER STYLES") },
            navigationIcon = {
                IconButton(onClick = { navController.popBackStack() }) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                }
            }
        )
    }) { innerPadding ->
        Column(modifier = Modifier.padding(innerPadding).padding(16.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
            Text("English Font Size: ${engSize.toInt()}px")
            Slider(engSize, { engSize = it; settings.englishFontSize = it.toInt() }, valueRange = 14f..40f)
            Text("Ancient Font Size: ${ancSize.toInt()}px")
            Slider(ancSize, { ancSize = it; settings.ancientFontSize = it.toInt() }, valueRange = 14f..40f)
            HorizontalDivider()
            SettingToggle(
                "Show Ethiopian Canon",
                "Include SirateTsion, Tizaz, Enoch, Jubilees, and other Ethiopian-canon books in the book selection grid",
                showEthiopian
            ) {
                showEthiopian = it
                settings.showEthiopianCanon = it
            }
            SettingToggle(
                "Show Apocrypha",
                "Include Tobit, Judith, Wisdom, and Sirach in the book selection grid",
                showApocrypha
            ) {
                showApocrypha = it
                settings.showApocrypha = it
            }
            HorizontalDivider()
            Text("ADVANCED — BIBLE TRADITION")
            SettingToggle(
                "Use Hebrew Masoretic Text",
                "By default the Old Testament reads from the Greek Septuagint (LXX) — the text quoted throughout the New Testament — paired with the Greek New Testament interlinear. Enable this to switch to the Hebrew Masoretic Text and NKJV instead. The New Testament always stays Greek.",
                useMasoretic
            ) {
                useMasoretic = it
                settings.otTextTradition = if (it) "masoretic" else "septuagint"
            }
        }
    }
}
