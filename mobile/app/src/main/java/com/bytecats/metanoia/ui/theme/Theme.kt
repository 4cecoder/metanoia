package com.bytecats.metanoia.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

@Composable
fun MetanoiaTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = darkColorScheme(
            primary = Color(0xFF7aa2f7),
            surface = Color(0xFF1a1b26),
            surfaceVariant = Color(0xFF24283b)
        ),
        content = content
    )
}
