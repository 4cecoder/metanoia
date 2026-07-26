package com.bytecats.metanoia.ui.components.bible

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Notes
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.Translate
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDirection
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bytecats.metanoia.models.InterlinearWord
import com.bytecats.metanoia.models.Verse

fun hasHebrewChars(text: String): Boolean =
    text.any { it in '\u0590'..'\u05FF' || it in '\uFB1D'..'\uFB4F' }

/**
 * A single verse in the reader: verse number row + main text + optional interlinear expansion.
 */
@OptIn(ExperimentalFoundationApi::class, ExperimentalLayoutApi::class)
@Composable
fun VerseItem(
    verse: Verse,
    isCurrent: Boolean,
    isExpanded: Boolean,
    highlight: Int,
    hasNotes: Boolean,
    englishFontSize: Int,
    ancientFontSize: Int,
    interlinearWords: List<InterlinearWord>,
    onSpeak: (String) -> Unit,
    onToggleInterlinear: () -> Unit,
    onLongPress: () -> Unit,
    onWordClick: (InterlinearWord) -> Unit,
    modifier: Modifier = Modifier,
) {
    val vs = verse.number
    val text = verse.text
    val hebrew = hasHebrewChars(text)
    val haptic = LocalHapticFeedback.current

    Column(
        modifier = modifier
            .padding(vertical = 12.dp)
            .combinedClickable(
                onClick = { },
                onLongClick = {
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    onLongPress()
                }
            )
    ) {
        // Verse number + controls row
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                "$vs",
                color = if (isCurrent) MaterialTheme.colorScheme.primary
                        else MaterialTheme.colorScheme.primary.copy(0.6f),
                fontWeight = if (isCurrent) FontWeight.Black else FontWeight.Bold
            )
            Spacer(modifier = Modifier.width(8.dp))
            if (hasNotes) {
                Icon(
                    Icons.AutoMirrored.Filled.Notes,
                    contentDescription = "Notes",
                    modifier = Modifier.size(14.dp),
                    tint = MaterialTheme.colorScheme.outline
                )
            }
            IconButton(
                onClick = { onSpeak(text) },
                modifier = Modifier.size(24.dp)
            ) {
                Icon(
                    Icons.AutoMirrored.Filled.VolumeUp,
                    contentDescription = "Read",
                    modifier = Modifier.size(16.dp),
                    tint = if (isCurrent) MaterialTheme.colorScheme.primary
                           else MaterialTheme.colorScheme.outline
                )
            }
            Spacer(modifier = Modifier.weight(1f))
            IconButton(
                onClick = onToggleInterlinear,
                modifier = Modifier.size(24.dp)
            ) {
                Icon(
                    if (isExpanded) Icons.Default.VisibilityOff else Icons.Default.Translate,
                    contentDescription = "Interlinear",
                    modifier = Modifier.size(16.dp)
                )
            }
        }

        // Main verse text — RTL + larger font for Hebrew, LTR + normal for English
        // Uses Unicode bidi override (\u202E..\u202C) to force RTL at the
        // text-engine level regardless of parent layout context. Relying on
        // textDirection/LayoutDirection alone doesn't work reliably when the
        // text composable sits inside an LTR column in a LazyColumn — the
        // bidi override is the only thing that guarantees correct word order
        // everywhere.
        val displayText = if (hebrew) "\u202E$text\u202C" else text
        Text(
            text = displayText,
            fontSize = if (hebrew) ancientFontSize.sp else englishFontSize.sp,
            fontWeight = if (isCurrent) FontWeight.Medium else FontWeight.Light,
            modifier = Modifier.background(
                verseBackground(isCurrent, highlight, MaterialTheme.colorScheme.primary),
                RoundedCornerShape(4.dp)
            )
        )

        // Interlinear expansion
        if (isExpanded) {
            CompositionLocalProvider(
                LocalLayoutDirection provides (if (hebrew) LayoutDirection.Rtl else LayoutDirection.Ltr)
            ) {
                FlowRow(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 8.dp)
                        .background(
                            MaterialTheme.colorScheme.surfaceVariant.copy(0.3f),
                            RoundedCornerShape(12.dp)
                        )
                        .padding(12.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    interlinearWords.forEach { word ->
                        InterlinearWordItem(
                            word = word,
                            ancientFontSize = ancientFontSize,
                            onClick = { onWordClick(word) }
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun InterlinearWordItem(
    word: InterlinearWord,
    ancientFontSize: Int,
    onClick: () -> Unit,
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier.clickable(onClick = onClick)
    ) {
        Text(
            word.original,
            color = if (word.strongs.startsWith("G")) Color(0xFF7aa2f7) else Color(0xFFe0af68),
            fontSize = ancientFontSize.sp,
            fontWeight = FontWeight.Bold
        )
        Text(
            word.translation,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.outline
        )
    }
}

private fun verseBackground(isCurrent: Boolean, highlight: Int, primary: Color): Color {
    return when {
        isCurrent -> primary.copy(0.15f)
        highlight != 0 -> Color(highlight.toLong()).copy(alpha = 0.3f)
        else -> Color.Transparent
    }
}
