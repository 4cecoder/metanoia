package com.bytecats.metanoia.ui.screens

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.*
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.*
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Notes
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bytecats.metanoia.bible.ReadingStats
import com.bytecats.metanoia.models.BibleBook
import com.bytecats.metanoia.models.InterlinearWord
import com.bytecats.metanoia.models.SearchResult
import com.bytecats.metanoia.models.Verse
import com.bytecats.metanoia.ui.components.HighlightedText
import com.bytecats.metanoia.viewmodel.MainViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class, ExperimentalFoundationApi::class)
@Composable
fun BibleScreen(viewModel: MainViewModel, onNavigateToSettings: () -> Unit = {}) {
    val bibleManager = viewModel.bibleManager
    val settings = viewModel.settingsManager
    val narration by viewModel.narrationState
    
    var step by remember { mutableStateOf("book") } 
    var selectedBook by remember { mutableStateOf<BibleBook?>(null) }
    var selectedChapter by remember { mutableStateOf(1) }
    var currentChapterContent by remember { mutableStateOf<List<Pair<Int, String>>>(emptyList()) }
    var interlinearData by remember(selectedBook, selectedChapter) { mutableStateOf<Map<Int, List<InterlinearWord>>>(emptyMap()) }
    var highlights by remember(selectedBook, selectedChapter) { mutableStateOf<Map<Int, Int>>(emptyMap()) }
    var expandedVerses by remember(selectedBook, selectedChapter) { mutableStateOf<Set<Int>>(emptySet()) }
    var chapterWordCounts by remember(selectedBook) { mutableStateOf<Map<Int, Int>>(emptyMap()) }
    var downloadedChapters by remember(selectedBook) { mutableStateOf<Set<Int>>(emptySet()) }
    
    LaunchedEffect(selectedBook) {
        if (selectedBook != null) {
            withContext(Dispatchers.IO) {
                chapterWordCounts = bibleManager.getChapterWordCounts(selectedBook!!.name)
                downloadedChapters = bibleManager.getDownloadedChapters(selectedBook!!.name)
            }
        }
    }
    
    var studyVerse by remember { mutableStateOf<Int?>(null) }
    var lexiconWord by remember { mutableStateOf<InterlinearWord?>(null) }
    var lexiconDetail by remember { mutableStateOf(Pair("", "Loading...")) }
    var modalBook by remember { mutableStateOf<BibleBook?>(null) }
    var showStudySheet by remember { mutableStateOf(false) }
    var showLexiconSheet by remember { mutableStateOf(false) }
    var isSearchVisible by remember { mutableStateOf(true) }
    var searchQuery by remember { mutableStateOf("") }
    var searchResults by remember { mutableStateOf<List<SearchResult>>(emptyList()) }
    
    val haptic = LocalHapticFeedback.current
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()
    val completionMap = remember { bibleManager.getBookCompletion() }
    val allBooks = bibleManager.books

    fun navigate(dir: Int) {
        val b = selectedBook ?: return
        var nCh = selectedChapter + dir; var nB = b
        if (nCh > b.chapters) { val idx = allBooks.indexOf(b); if (idx < allBooks.size - 1) { nB = allBooks[idx+1]; nCh = 1 } else return }
        else if (nCh < 1) { val idx = allBooks.indexOf(b); if (idx > 0) { nB = allBooks[idx-1]; nCh = nB.chapters } else return }
        viewModel.stopNarration(); selectedBook = nB; selectedChapter = nCh; expandedVerses = emptySet()
        scope.launch { 
            val c = withContext(Dispatchers.IO) { bibleManager.getChapter(nB.name, nCh) }
            val hl = withContext(Dispatchers.IO) { bibleManager.getHighlights(nB.name, nCh) }
            currentChapterContent = c; highlights = hl; listState.scrollToItem(0) 
        }
    }

    LaunchedEffect(narration.currentVerse) { 
        if (narration.isPlaying && narration.currentVerse != -1) { 
            val idx = currentChapterContent.indexOfFirst { it.first == narration.currentVerse }
            if (idx != -1) listState.animateScrollToItem(idx) 
        } 
    }

    Scaffold(
        topBar = {
            Column {
                TopAppBar(
                    title = { Text(if (step == "read") "${selectedBook?.name} $selectedChapter" else "BIBLE") },
                    navigationIcon = { if (step != "book") IconButton({ step = if (step == "read") "chapter" else "book"; isSearchVisible = (step == "book"); viewModel.stopNarration() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, null) } },
                    actions = { 
                        IconButton({ isSearchVisible = !isSearchVisible }) { Icon(Icons.Default.Search, null) }
                        IconButton({ onNavigateToSettings() }) { Icon(Icons.Default.Settings, null) }
                        if (step == "read") {
                            if (narration.isPlaying) IconButton({ viewModel.stopNarration() }) { Icon(Icons.Default.StopCircle, null, tint = Color.Red) }
                            else IconButton({ viewModel.startChapterNarration(currentChapterContent.map { (num, txt) -> Verse(num, txt) }) }) { Icon(Icons.Default.PlayCircle, null) }
                            IconButton({ scope.launch {
                                try {
                                    bibleManager.scrapeChapter(selectedBook!!.name, selectedChapter, settings.bibleGatewayVersion)
                                    currentChapterContent = bibleManager.getChapter(selectedBook!!.name, selectedChapter)
                                    highlights = bibleManager.getHighlights(selectedBook!!.name, selectedChapter)
                                    // Interlinear is optional - skip if unavailable (e.g., apocrypha)
                                    try {
                                        bibleManager.scrapeInterlinear(selectedBook!!.name, selectedChapter)
                                    } catch (e: Exception) {
                                        android.util.Log.w("BibleScreen", "Interlinear not available for ${selectedBook!!.name} $selectedChapter: ${e.message}")
                                    }
                                } catch (e: Exception) {
                                    android.util.Log.e("BibleScreen", "Failed to fetch chapter: ${e.message}", e)
                                }
                            } }) { Icon(Icons.Default.CloudDownload, null) } 
                        }
                    }
                )
                AnimatedVisibility(visible = isSearchVisible || searchQuery.isNotEmpty()) {
                    SearchBar(
                        query = searchQuery, 
                        onQueryChange = { searchQuery = it; searchResults = bibleManager.searchVerses(it) }, 
                        onSearch = { }, 
                        active = searchQuery.isNotEmpty(), 
                        onActiveChange = { if (!it) searchQuery = "" }, 
                        placeholder = { Text("Search scripture...") }, 
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)
                    ) {
                        LazyColumn(modifier = Modifier.fillMaxSize()) {
                            items(searchResults) { res ->
                                ListItem(
                                    headlineContent = { Text("${res.book} ${res.chapter}:${res.verse}", fontWeight = FontWeight.Bold) }, 
                                    supportingContent = { HighlightedText(res.text, searchQuery) }, 
                                    modifier = Modifier.clickable { 
                                        selectedBook = bibleManager.books.find { it.name == res.book }
                                        selectedChapter = res.chapter
                                        currentChapterContent = bibleManager.getChapter(res.book, res.chapter)
                                        highlights = bibleManager.getHighlights(res.book, res.chapter)
                                        searchQuery = ""; isSearchVisible = false; step = "read" 
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }
    ) { innerPadding ->
        var dragOffset by remember { mutableStateOf(0f) }
        var hasTriggered by remember { mutableStateOf(false) }
        Column(modifier = Modifier.padding(innerPadding).fillMaxSize().pointerInput(Unit) { 
            detectDragGestures(
                onDragStart = { dragOffset = 0f; hasTriggered = false },
                onDragEnd = { hasTriggered = false },
                onDragCancel = { hasTriggered = false }
            ) { change, amount -> 
                if (step == "read") { 
                    change.consume(); dragOffset += amount.x
                    if (!hasTriggered) { 
                        if (dragOffset < -150f) { navigate(1); hasTriggered = true; haptic.performHapticFeedback(HapticFeedbackType.LongPress) } 
                        else if (dragOffset > 150f) { navigate(-1); hasTriggered = true; haptic.performHapticFeedback(HapticFeedbackType.LongPress) } 
                    } 
                } 
            } 
        }) {
            when (step) {
                "book" -> {
                    LazyVerticalGrid(columns = GridCells.Fixed(3), modifier = Modifier.padding(12.dp)) {
                        listOf("Old" to "Old Testament", "New" to "New Testament", "Eth" to "Ethiopian").forEach { (key, label) ->
                            item(span = { GridItemSpan(maxLineSpan) }) { Text(label, modifier = Modifier.padding(16.dp), color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.Bold) }
                            items(bibleManager.books.filter { it.testament == key }) { book ->
                                val progress = completionMap[book.name] ?: 0f
                                val baseColor = 0x1A1B26
                                val readGreen = 0x9ECE6A
                                val lerpedColorInt = ReadingStats.lerpColor(baseColor, readGreen, progress)
                                val containerColor = if (progress > 0f) Color(lerpedColorInt).copy(alpha = if (progress >= 1f) 0.35f else 0.2f) else MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f)
                                Card(
                                    modifier = Modifier.padding(4.dp).height(68.dp).combinedClickable(
                                        onClick = { selectedBook = book; step = "chapter"; isSearchVisible = false },
                                        onLongClick = { haptic.performHapticFeedback(HapticFeedbackType.LongPress); modalBook = book }
                                    ),
                                    colors = CardDefaults.cardColors(containerColor = containerColor),
                                    border = if (progress >= 1f) BorderStroke(1.5.dp, Color(0xFF9ece6a)) else if (progress > 0f) BorderStroke(1.dp, Color(0xFFe0af68).copy(0.6f)) else null
                                ) {
                                    Column(
                                        modifier = Modifier.fillMaxSize().padding(horizontal = 6.dp, vertical = 6.dp),
                                        verticalArrangement = Arrangement.SpaceBetween,
                                        horizontalAlignment = Alignment.CenterHorizontally
                                    ) {
                                        Text(book.name, textAlign = TextAlign.Center, style = MaterialTheme.typography.labelMedium, maxLines = 1)
                                        if (progress > 0f) {
                                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                                LinearProgressIndicator(
                                                    progress = { progress.coerceIn(0f, 1f) },
                                                    modifier = Modifier.fillMaxWidth().height(4.dp),
                                                    color = if (progress >= 1f) Color(0xFF9ece6a) else Color(0xFFe0af68),
                                                    trackColor = MaterialTheme.colorScheme.outline.copy(alpha = 0.2f),
                                                    strokeCap = androidx.compose.ui.graphics.StrokeCap.Round
                                                )
                                                Text("%.0f%%".format(progress * 100), style = MaterialTheme.typography.labelSmall, fontSize = 9.sp, color = if (progress >= 1f) Color(0xFF9ece6a) else Color(0xFFe0af68), fontWeight = FontWeight.Bold)
                                            }
                                        } else {
                                            Text("${book.chapters} ch", style = MaterialTheme.typography.labelSmall, fontSize = 9.sp, color = MaterialTheme.colorScheme.outline)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                "chapter" -> {
                    val totalWords = ReadingStats.calculateBookWordCount(chapterWordCounts)
                    val avgWords = if ((selectedBook?.chapters ?: 0) > 0) totalWords / selectedBook!!.chapters else 0
                    val readTime = ReadingStats.formatReadingTime(totalWords)

                    Column(modifier = Modifier.fillMaxSize()) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 16.dp, vertical = 8.dp)
                                .background(Color(0xFF1a1b26).copy(alpha = 0.8f), RoundedCornerShape(8.dp))
                                .border(1.dp, Color(0xFF7aa2f7).copy(alpha = 0.5f), RoundedCornerShape(8.dp))
                                .padding(12.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                Text("TOTAL WORDS", fontSize = 10.sp, color = Color(0xFF7aa2f7), fontWeight = FontWeight.Bold, letterSpacing = 1.sp)
                                Text("$totalWords", fontSize = 16.sp, color = Color(0xFFc0caf5), fontWeight = FontWeight.Black)
                            }
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                Text("AVG/CHAPTER", fontSize = 10.sp, color = Color(0xFF9ece6a), fontWeight = FontWeight.Bold, letterSpacing = 1.sp)
                                Text("$avgWords", fontSize = 16.sp, color = Color(0xFFc0caf5), fontWeight = FontWeight.Black)
                            }
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                Text("READ TIME", fontSize = 10.sp, color = Color(0xFFbb9af7), fontWeight = FontWeight.Bold, letterSpacing = 1.sp)
                                Text(readTime, fontSize = 16.sp, color = Color(0xFFc0caf5), fontWeight = FontWeight.Black)
                            }
                        }

                        LazyVerticalGrid(columns = GridCells.Fixed(5), modifier = Modifier.padding(16.dp)) {
                            items((1..(selectedBook?.chapters ?: 1)).toList()) { ch ->
                                val wordCount = chapterWordCounts[ch] ?: 0
                                val isDownloaded = downloadedChapters.contains(ch)
                                Card(
                                    modifier = Modifier.padding(4.dp).aspectRatio(1f).clickable { 
                                        selectedChapter = ch; 
                                        currentChapterContent = bibleManager.getChapter(selectedBook!!.name, ch); 
                                        highlights = bibleManager.getHighlights(selectedBook!!.name, ch); 
                                        step = "read" 
                                    },
                                    colors = CardDefaults.cardColors(containerColor = if (isDownloaded) Color(0xFF9ece6a).copy(alpha = 0.1f) else MaterialTheme.colorScheme.surfaceVariant),
                                    border = if (isDownloaded) BorderStroke(1.dp, Color(0xFF9ece6a)) else BorderStroke(0.5.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.3f))
                                ) { 
                                    Box(modifier = Modifier.fillMaxSize()) { 
                                        Text("$ch", modifier = Modifier.align(Alignment.Center)) 
                                        if (wordCount > 0) {
                                            Text(
                                                text = "$wordCount",
                                                modifier = Modifier.align(Alignment.BottomEnd).padding(end = 4.dp, bottom = 2.dp),
                                                fontSize = 8.sp,
                                                color = Color(0xFF7aa2f7).copy(alpha = 0.8f),
                                                fontWeight = FontWeight.Medium,
                                                style = androidx.compose.ui.text.TextStyle(fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace)
                                            )
                                        }
                                    } 
                                }
                            }
                        }
                    }
                }
                "read" -> {
                    LazyColumn(state = listState, modifier = Modifier.fillMaxSize().padding(horizontal = 16.dp)) {
                        items(currentChapterContent) { (vs, text) ->
                            val isExpanded = expandedVerses.contains(vs)
                            val hl = highlights[vs] ?: 0
                            val isCurrent = narration.isPlaying && narration.currentVerse == vs
                            val hasNotes = bibleManager.getNotes(selectedBook!!.name, selectedChapter, vs).isNotEmpty()
                            val isHebrew = selectedBook?.testament == "Old"
                            
                            Column(modifier = Modifier.padding(vertical = 12.dp).combinedClickable(onClick = { }, onLongClick = { haptic.performHapticFeedback(HapticFeedbackType.LongPress); studyVerse = vs; showStudySheet = true })) {
                                Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                                    Text("$vs", color = if (isCurrent) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.primary.copy(0.6f), fontWeight = if (isCurrent) FontWeight.Black else FontWeight.Bold)
                                    Spacer(modifier = Modifier.width(8.dp))
                                    if (hasNotes) Icon(Icons.AutoMirrored.Filled.Notes, "Notes", modifier = Modifier.size(14.dp), tint = MaterialTheme.colorScheme.outline)
                                    IconButton({ viewModel.speak(text) }, modifier = Modifier.size(24.dp)) { Icon(Icons.AutoMirrored.Filled.VolumeUp, "Read", modifier = Modifier.size(16.dp), tint = if (isCurrent) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline) }
                                    Spacer(modifier = Modifier.weight(1f))
                                    IconButton(onClick = { expandedVerses = if (isExpanded) expandedVerses - vs else expandedVerses + vs; if (!isExpanded && !interlinearData.containsKey(vs)) interlinearData = interlinearData + (vs to bibleManager.getInterlinear(selectedBook!!.name, selectedChapter, vs)) }, modifier = Modifier.size(24.dp)) { Icon(if (isExpanded) Icons.Default.VisibilityOff else Icons.Default.Translate, "Interlinear", modifier = Modifier.size(16.dp)) }
                                }
                                Text(text, fontSize = settings.englishFontSize.sp, fontWeight = if (isCurrent) FontWeight.Medium else FontWeight.Light, modifier = Modifier.background(if (isCurrent) MaterialTheme.colorScheme.primary.copy(0.15f) else if (hl != 0) Color(hl.toLong()).copy(alpha = 0.3f) else Color.Transparent, RoundedCornerShape(4.dp)))
                                if (isExpanded) {
                                    CompositionLocalProvider(LocalLayoutDirection provides (if (isHebrew) LayoutDirection.Rtl else LayoutDirection.Ltr)) {
                                        FlowRow(modifier = Modifier.fillMaxWidth().padding(top = 8.dp).background(MaterialTheme.colorScheme.surfaceVariant.copy(0.3f), RoundedCornerShape(12.dp)).padding(12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                            interlinearData[vs]?.forEach { word ->
                                                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.clickable { lexiconWord = word; showLexiconSheet = true; scope.launch { val det = bibleManager.getLexiconDetail(word.strongs); lexiconDetail = if (det.second.isEmpty()) { bibleManager.scrapeStrong(word.strongs, selectedBook?.name); bibleManager.getLexiconDetail(word.strongs) } else det; if (settings.speakDefinitionsOnTap) viewModel.speak(lexiconDetail.second) } }) {
                                                    Text(word.original, color = if (word.strongs.startsWith("G")) Color(0xFF7aa2f7) else Color(0xFFe0af68), fontSize = settings.ancientFontSize.sp, fontWeight = FontWeight.Bold)
                                                    Text(word.translation, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.outline)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    if (showStudySheet && studyVerse != null) {
        ModalBottomSheet(onDismissRequest = { showStudySheet = false }) {
            var newNoteText by remember { mutableStateOf("") }
            val notes = bibleManager.getNotes(selectedBook!!.name, selectedChapter, studyVerse!!)
            Column(modifier = Modifier.padding(24.dp).fillMaxWidth().verticalScroll(rememberScrollState())) {
                Text("${selectedBook?.name} $selectedChapter:$studyVerse", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Black)
                Spacer(modifier = Modifier.height(16.dp)); Text("Highlight Color", style = MaterialTheme.typography.labelLarge)
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    listOf(0xFFFF9E6A, 0xFF9ECE6A, 0xFF7AA2F7, 0xFFBB9AF7, 0).forEach { color -> 
                        Box(modifier = Modifier.size(40.dp).background(if (color.toLong() == 0L) Color.Transparent else Color(color.toLong()), CircleShape).border(1.dp, MaterialTheme.colorScheme.outline, CircleShape).clickable { bibleManager.setHighlight(selectedBook!!.name, selectedChapter, studyVerse!!, color.toInt()); highlights = bibleManager.getHighlights(selectedBook!!.name, selectedChapter) }) { if (color.toLong() == 0L) Icon(Icons.Default.Close, null, modifier = Modifier.align(Alignment.Center)) } 
                    }
                }
                Spacer(modifier = Modifier.height(24.dp)); Text("Study Notes", style = MaterialTheme.typography.labelLarge)
                notes.forEach { note -> Card(modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)) { Text(note.content, modifier = Modifier.padding(12.dp), style = MaterialTheme.typography.bodyMedium) } }
                OutlinedTextField(newNoteText, { newNoteText = it }, modifier = Modifier.fillMaxWidth(), placeholder = { Text("Enter insight...") })
                Button(onClick = { if (newNoteText.isNotEmpty()) { bibleManager.saveNote(selectedBook!!.name, selectedChapter, studyVerse!!, newNoteText); newNoteText = "" } }, modifier = Modifier.align(Alignment.End).padding(top = 8.dp)) { Text("Save Note") }
                Spacer(modifier = Modifier.height(40.dp))
            }
        }
    }

    if (showLexiconSheet && lexiconWord != null) {
        com.bytecats.metanoia.ui.components.bible.LexiconSheet(
            word = lexiconWord!!,
            detail = com.bytecats.metanoia.models.LexiconEntry(lexiconDetail.first, lexiconDetail.second),
            onDismiss = { showLexiconSheet = false; lexiconDetail = Pair("", "Loading...") },
            onSpeak = { viewModel.speak(it) },
            onFavorite = { strongs, lemma, def -> bibleManager.saveFavorite(strongs, lemma, def) }
        )
    }

    if (modalBook != null) {
        val targetBook = modalBook!!
        var isDownloadingBook by remember { mutableStateOf(false) }
        var downloadStatusText by remember { mutableStateOf("") }

        AlertDialog(
            onDismissRequest = { if (!isDownloadingBook) modalBook = null },
            title = { Text(targetBook.name, fontWeight = FontWeight.Black, style = MaterialTheme.typography.headlineSmall, color = MaterialTheme.colorScheme.primary) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("${targetBook.chapters} Chapters • ${targetBook.testament} Testament • ${targetBook.textTradition.name}", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.outline)
                    if (isDownloadingBook) {
                        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                            Text(downloadStatusText, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
                        }
                    } else {
                        Button(
                            onClick = {
                                selectedBook = targetBook
                                step = "chapter"
                                modalBook = null
                            },
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Text("Open Chapter Selection")
                        }
                        OutlinedButton(
                            onClick = {
                                scope.launch {
                                    isDownloadingBook = true
                                    try {
                                        for (ch in 1..targetBook.chapters) {
                                            downloadStatusText = "Downloading Chapter $ch / ${targetBook.chapters}..."
                                            withContext(Dispatchers.IO) {
                                                bibleManager.scrapeChapter(targetBook.name, ch, settings.bibleGatewayVersion)
                                                try { bibleManager.scrapeInterlinear(targetBook.name, ch) } catch (_: Exception) {}
                                            }
                                        }
                                        downloadStatusText = "Complete!"
                                    } catch (e: Exception) {
                                        downloadStatusText = "Error: ${e.message}"
                                    } finally {
                                        isDownloadingBook = false
                                        modalBook = null
                                    }
                                }
                            },
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Icon(Icons.Default.CloudDownload, contentDescription = null, modifier = Modifier.size(18.dp))
                            Spacer(modifier = Modifier.width(8.dp))
                            Text("Download Entire Book")
                        }
                    }
                }
            },
            confirmButton = {},
            dismissButton = {
                if (!isDownloadingBook) {
                    TextButton(onClick = { modalBook = null }) { Text("Close") }
                }
            }
        )
    }
}
