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
import com.bytecats.metanoia.bible.BibleBook
import com.bytecats.metanoia.bible.InterlinearWord
import com.bytecats.metanoia.bible.SearchResult
import com.bytecats.metanoia.ui.components.HighlightedText
import com.bytecats.metanoia.viewmodel.MainViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class, ExperimentalFoundationApi::class)
@Composable
fun BibleScreen(viewModel: MainViewModel) {
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
    
    var studyVerse by remember { mutableStateOf<Int?>(null) }
    var lexiconWord by remember { mutableStateOf<InterlinearWord?>(null) }
    var lexiconDetail by remember { mutableStateOf(Pair("", "Loading...")) }
    var showStudySheet by remember { mutableStateOf(false) }
    var showLexiconSheet by remember { mutableStateOf(false) }
    var isSearchVisible by remember { mutableStateOf(true) }
    var searchQuery by remember { mutableStateOf("") }
    var searchResults by remember { mutableStateOf<List<SearchResult>>(emptyList()) }
    
    val haptic = LocalHapticFeedback.current
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()
    val completionMap = remember { bibleManager.getBookCompletion() }

    fun navigate(dir: Int) {
        val b = selectedBook ?: return
        var nCh = selectedChapter + dir; var nB = b
        if (nCh > b.chapters) { val idx = bibleManager.books.indexOf(b); if (idx < bibleManager.books.size - 1) { nB = bibleManager.books[idx+1]; nCh = 1 } else return }
        else if (nCh < 1) { val idx = bibleManager.books.indexOf(b); if (idx > 0) { nB = bibleManager.books[idx-1]; nCh = nB.chapters } else return }
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
                        if (step == "read") {
                            if (narration.isPlaying) IconButton({ viewModel.stopNarration() }) { Icon(Icons.Default.StopCircle, null, tint = Color.Red) }
                            else IconButton({ viewModel.startChapterNarration(currentChapterContent) }) { Icon(Icons.Default.PlayCircle, null) }
                            IconButton({ scope.launch { bibleManager.scrapeChapter(selectedBook!!.name, selectedChapter, settings.bibleGatewayVersion); bibleManager.scrapeInterlinear(selectedBook!!.name, selectedChapter); currentChapterContent = bibleManager.getChapter(selectedBook!!.name, selectedChapter); highlights = bibleManager.getHighlights(selectedBook!!.name, selectedChapter) } }) { Icon(Icons.Default.CloudDownload, null) } 
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
                                Card(modifier = Modifier.padding(4.dp).height(64.dp).clickable { selectedBook = book; step = "chapter"; isSearchVisible = false }, colors = CardDefaults.cardColors(containerColor = if (progress >= 1f) Color(0xFF9ece6a).copy(alpha = 0.2f) else if (progress > 0f) Color(0xFFe0af68).copy(0.2f) else MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f)), border = if (progress >= 1f) BorderStroke(1.dp, Color(0xFF9ece6a)) else null) { Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Text(book.name, textAlign = TextAlign.Center, style = MaterialTheme.typography.labelMedium) } }
                            }
                        }
                    }
                }
                "chapter" -> {
                    LazyVerticalGrid(columns = GridCells.Fixed(5), modifier = Modifier.padding(16.dp)) {
                        items((1..(selectedBook?.chapters ?: 1)).toList()) { ch ->
                            Card(modifier = Modifier.padding(4.dp).aspectRatio(1f).clickable { selectedChapter = ch; currentChapterContent = bibleManager.getChapter(selectedBook!!.name, ch); highlights = bibleManager.getHighlights(selectedBook!!.name, ch); step = "read" }) { Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Text("$ch") } }
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
        ModalBottomSheet(onDismissRequest = { showLexiconSheet = false; lexiconDetail = Pair("", "Loading...") }) {
            Column(modifier = Modifier.padding(24.dp).fillMaxWidth().verticalScroll(rememberScrollState())) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) { Text(lexiconDetail.first.ifEmpty { lexiconWord!!.original }, style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Black, color = MaterialTheme.colorScheme.primary); Text(lexiconWord!!.strongs, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.outline) }
                    IconButton({ viewModel.speak(lexiconDetail.second) }) { Icon(Icons.AutoMirrored.Filled.VolumeUp, "Speak", tint = MaterialTheme.colorScheme.primary) }
                    IconButton({ bibleManager.saveFavorite(lexiconWord!!.strongs, lexiconDetail.first, lexiconDetail.second) }) { Icon(Icons.Default.Diamond, "Pin", tint = Color(0xFFbb9af7)) }
                }
                HorizontalDivider(modifier = Modifier.padding(vertical = 16.dp), color = MaterialTheme.colorScheme.outlineVariant)
                Text(lexiconDetail.second, style = MaterialTheme.typography.bodyLarge, lineHeight = 24.sp); Spacer(modifier = Modifier.height(40.dp))
            }
        }
    }
}
