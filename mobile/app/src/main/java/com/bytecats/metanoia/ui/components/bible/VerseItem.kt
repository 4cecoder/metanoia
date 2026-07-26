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
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
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
        // Hebrew uses a native Android TextView with TEXT_DIRECTION_RTL because
        // Compose's Text composable doesn't reliably honor bidi overrides or
        // textDirection when nested inside LTR columns in LazyColumn. The
        // native TextView handles sentence-level RTL correctly (first word on
        // the right, sentence flows right-to-left).
        if (hebrew) {
            val bgColor = verseBackground(isCurrent, highlight, MaterialTheme.colorScheme.primary)
            val textColorArgb = MaterialTheme.colorScheme.onSurface.toArgb()
            // Strip any LTR override markers that upstream text may have picked up.
            val cleanText = text.replace("\u202A", "").replace("\u202D", "").replace("\u202C", "")
            AndroidView(
                factory = { ctx ->
                    android.widget.TextView(ctx).apply {
                        textSize = ancientFontSize.toFloat()
                        layoutDirection = android.view.View.LAYOUT_DIRECTION_RTL
                        textDirection = android.view.View.TEXT_DIRECTION_RTL
                        textAlignment = android.view.View.TEXT_ALIGNMENT_VIEW_END
                        gravity = android.view.Gravity.END or android.view.Gravity.CENTER_VERTICAL
                        setTextColor(textColorArgb)
                        typeface = android.graphics.Typeface.SANS_SERIF
                    }
                },
                update = { tv ->
                    tv.text = cleanText
                    tv.setTextColor(textColorArgb)
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .background(bgColor, RoundedCornerShape(4.dp))
            )
        } else {
            Text(
                text = text,
                fontSize = englishFontSize.sp,
                fontWeight = if (isCurrent) FontWeight.Medium else FontWeight.Light,
                modifier = Modifier.background(
                    verseBackground(isCurrent, highlight, MaterialTheme.colorScheme.primary),
                    RoundedCornerShape(4.dp)
                )
            )
        }

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
