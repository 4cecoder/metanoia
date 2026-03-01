package com.bytecats.metanoia.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun ModuleCard(
    title: String,
    sub: String,
    icon: ImageVector,
    accent: Color,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    Card(
        onClick = onClick,
        modifier = modifier.height(130.dp).padding(4.dp),
        shape = RoundedCornerShape(24.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f))
    ) {
        Box(modifier = Modifier.fillMaxSize()) {
            Box(
                modifier = Modifier
                    .size(70.dp)
                    .offset(x = 10.dp, y = (-10).dp)
                    .background(Brush.radialGradient(listOf(accent.copy(alpha = 0.15f), Color.Transparent)), CircleShape)
                    .align(Alignment.TopEnd)
            )
            Column(
                modifier = Modifier.padding(16.dp).fillMaxSize(),
                verticalArrangement = Arrangement.SpaceBetween
            ) {
                Icon(icon, null, tint = accent, modifier = Modifier.size(28.dp))
                Column {
                    Text(title, fontWeight = FontWeight.Black, style = MaterialTheme.typography.titleMedium)
                    Text(sub, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.outline)
                }
            }
        }
    }
}

@Composable
fun StatItemCompact(label: String, value: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.width(130.dp)) {
        Text(
            value,
            fontWeight = FontWeight.Black,
            style = MaterialTheme.typography.headlineMedium,
            color = MaterialTheme.colorScheme.primary
        )
        Text(
            label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.outline,
            textAlign = TextAlign.Center
        )
    }
}

@Composable
fun HighlightedText(
    fullText: String,
    query: String,
    color: Color = MaterialTheme.colorScheme.primary
) {
    if (query.isEmpty()) {
        Text(fullText, maxLines = 2, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodySmall)
        return
    }
    val annotatedString = buildAnnotatedString {
        val lowerText = fullText.lowercase()
        val lowerQuery = query.lowercase()
        var start = 0
        while (start < fullText.length) {
            val idx = lowerText.indexOf(lowerQuery, start)
            if (idx == -1) {
                append(fullText.substring(start))
                break
            } else {
                append(fullText.substring(start, idx))
                withStyle(style = SpanStyle(fontWeight = FontWeight.Black, color = color, background = color.copy(0.15f))) {
                    append(fullText.substring(idx, idx + lowerQuery.length))
                }
                start = idx + lowerQuery.length
            }
        }
    }
    Text(annotatedString, maxLines = 2, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodySmall)
}

@Composable
fun ConfirmActionDialog(title: String, msg: String, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title, fontWeight = FontWeight.Black) },
        text = { Text(msg) }, 
        confirmButton = {
            Button(
                onClick = { onConfirm(); onDismiss() },
                colors = ButtonDefaults.buttonColors(containerColor = Color.Red)
            ) {
                Text("PURGE", fontWeight = FontWeight.Bold)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("CANCEL") }
        }
    )
}
