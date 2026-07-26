package com.bytecats.metanoia.ui.components.bible

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material3.Card
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

@Composable
fun ChapterGrid(
    chapterCount: Int,
    onChapterSelected: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyVerticalGrid(
        columns = GridCells.Fixed(5),
        modifier = modifier.padding(16.dp)
    ) {
        items((1..chapterCount).toList()) { ch ->
            Card(
                modifier = Modifier
                    .padding(4.dp)
                    .aspectRatio(1f)
                    .clickable { onChapterSelected(ch) }
            ) {
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center
                ) {
                    Text("$ch")
                }
            }
        }
    }
}
