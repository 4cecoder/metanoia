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
import androidx.navigation.NavController
import com.bytecats.metanoia.models.BibleBook
import com.bytecats.metanoia.models.InterlinearWord
import com.bytecats.metanoia.models.LexiconEntry
import com.bytecats.metanoia.models.SearchResult
import com.bytecats.metanoia.models.Verse
import com.bytecats.metanoia.ui.components.HighlightedText
import com.bytecats.metanoia.viewmodel.MainViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class, ExperimentalFoundationApi::class)
@Composable
fun BibleScreen(navController: NavController, viewModel: MainViewModel) {
    val bibleManager = viewModel.bibleManager
    val settings = viewModel.settingsManager
    val narration by viewModel.narrationState
    
    var step by remember { mutableStateOf("book") } 
    var selectedBook by remember { mutableStateOf<BibleBook?>(null) }
    var selectedChapter by remember { mutableStateOf(1) }
    var currentChapterContent by remember { mutableStateOf<List<Verse>>(emptyList()) }
    var interlinearData by remember(selectedBook, selectedChapter) { mutableStateOf<Map<Int, List<InterlinearWord>>>(emptyMap()) }
    var highlights by remember(selectedBook, selectedChapter) { mutableStateOf<Map<Int, Int>>(emptyMap()) }
    var expandedVerses by remember(selectedBook, selectedChapter) { mutableStateOf<Set<Int>>(emptySet()) }
    
    var studyVerse by remember { mutableStateOf<Int?>(null) }
    var lexiconWord by remember { mutableStateOf<InterlinearWord?>(null) }
    var lexiconDetail by remember { mutableStateOf(LexiconEntry("", "Loading...")) }
    var showStudySheet by remember { mutableStateOf(false) }
    var showLexiconSheet by remember { mutableStateOf(false) }
    var showVoiceSheet by remember { mutableStateOf(false) }
    var isSearchVisible by remember { mutableStateOf(true) }
    var searchQuery by remember { mutableStateOf("") }
    var searchResults by remember { mutableStateOf<List<SearchResult>>(emptyList()) }
    
    val haptic = LocalHapticFeedback.current
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()
    var completionMap by remember { mutableStateOf(bibleManager.getBookCompletion()) }
    val snackbarHostState = remember { SnackbarHostState() }
    val scrapeError by bibleManager.scrapeError.collectAsState()

    // Best-effort background prefetch of every not-yet-cached chapter in a
    // book, kicked off the moment its card is tapped (see the "book" step
    // grid below) rather than waiting for the user to open each chapter one
    // at a time. Sequential, not parallel: this app's scraping fallback
    // (BibleScraper, biblehub.com) is a single external site with no known
    // rate-limit headroom to spend — hammering it with dozens of concurrent
    // requests for one bulk prefetch risks getting the whole app rate
    // -limited/blocked for everyone, not just this download. fetchChapter
    // already checks the local cache first and returns immediately for
    // chapters that are already downloaded, so calling it unconditionally
    // for every chapter (rather than pre-filtering) costs nothing extra for
    // the ones already cached. Deliberately swallows per-chapter failures
    // (network down partway through, a chapter with no source, etc.)
    // instead of surfacing each one through the shared scrapeError Snackbar
    // channel below -- that channel is meant for "the chapter you're
    // actively looking at failed to load," and reusing it here would spam
    // one Snackbar per failed chapter during a background prefetch the user
    // didn't explicitly ask to watch.
    fun prefetchBook(book: BibleBook) {
        if ((completionMap[book.name] ?: 0f) >= 1f) return // already fully cached
        scope.launch(Dispatchers.IO) {
            for (ch in 1..book.chapters) {
                try {
                    bibleManager.fetchChapter(book.name, ch, settings.bibleGatewayVersion)
                } catch (e: Exception) {
                    // Best-effort: move on to the next chapter regardless.
                }
            }
            completionMap = bibleManager.getBookCompletion()
        }
    }

    // Surface scrape/network failures instead of leaving the screen looking
    // like it's "still loading" forever with no error and no retry signal.
    fun retryDownload() {
        val b = selectedBook ?: return
        scope.launch {
            bibleManager.scrapeChapter(b.name, selectedChapter, settings.bibleGatewayVersion)
            bibleManager.scrapeInterlinear(b.name, selectedChapter)
            currentChapterContent = bibleManager.getChapter(b.name, selectedChapter)
            highlights = bibleManager.getHighlights(b.name, selectedChapter)
        }
    }

    LaunchedEffect(scrapeError) {
        scrapeError?.let {
            val result = snackbarHostState.showSnackbar(it, actionLabel = "Retry", withDismissAction = true)
            if (result == SnackbarResult.ActionPerformed) retryDownload()
        }
    }

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
            val idx = currentChapterContent.indexOfFirst { it.number == narration.currentVerse }
            if (idx != -1) listState.animateScrollToItem(idx)
        }
    }

    // Deep link (metanoia://bible/... or an https App Link — see
    // com.bytecats.metanoia.bible.DeepLink / docs/ANDROID_DEEP_LINKS.md)
    // landed on a specific book/chapter/verse. Jumps straight to "read",
    // bypassing the book/chapter pickers, the same way a search-result tap
    // already does — except using fetchChapter (local cache, then
    // gateway/scrape) instead of getChapter (local-only), since a shared
    // link is likely to point at a chapter the recipient hasn't opened
    // before and so doesn't have cached yet.
    LaunchedEffect(viewModel.pendingDeepLink) {
        val target = viewModel.pendingDeepLink ?: return@LaunchedEffect
        val book = bibleManager.books.find { it.name == target.book }
        if (book == null) {
            viewModel.pendingDeepLink = null
            return@LaunchedEffect
        }
        viewModel.stopNarration()
        selectedBook = book
        selectedChapter = target.chapter
        isSearchVisible = false
        val content = withContext(Dispatchers.IO) { bibleManager.fetchChapter(book.name, target.chapter, settings.bibleGatewayVersion) }
        val hl = withContext(Dispatchers.IO) { bibleManager.getHighlights(book.name, target.chapter) }
        currentChapterContent = content
        highlights = hl
        step = "read"
        viewModel.pendingDeepLink = null // consume once — back-navigating here shouldn't replay the jump
        target.verse?.let { v ->
            val idx = content.indexOfFirst { it.number == v }
            if (idx != -1) listState.scrollToItem(idx)
        }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            Column {
                TopAppBar(
                    title = { Text(if (step == "read") "${selectedBook?.name} $selectedChapter" else "BIBLE") },
                    navigationIcon = {
                        IconButton({
                            if (step == "book") {
                                navController.popBackStack()
                            } else {
                                step = if (step == "read") "chapter" else "book"
                                isSearchVisible = (step == "book")
                                viewModel.stopNarration()
                            }
                        }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") }
                    },
                    actions = { 
                        if (viewModel.isRemoteTtsActive && narration.isPlaying) {
                            Surface(
                                color = Color(0xFF9ece6a).copy(alpha = 0.2f),
                                shape = RoundedCornerShape(4.dp),
                                border = BorderStroke(1.dp, Color(0xFF9ece6a)),
                                modifier = Modifier.padding(end = 8.dp)
                            ) {
                                Text(
                                    "NEURAL",
                                    modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                                    style = MaterialTheme.typography.labelSmall,
                                    color = Color(0xFF9ece6a),
                                    fontWeight = FontWeight.Black
                                )
                            }
                        }
                        IconButton({ isSearchVisible = !isSearchVisible }) { Icon(Icons.Default.Search, null) }
                        if (step == "read") {
                            if (narration.isPlaying) IconButton({ viewModel.stopNarration() }) { Icon(Icons.Default.StopCircle, null, tint = Color.Red) }
                            else IconButton(
                                onClick = { viewModel.startChapterNarration(currentChapterContent) },
                                modifier = Modifier.combinedClickable(
                                    onClick = { viewModel.startChapterNarration(currentChapterContent) },
                                    onLongClick = { 
                                        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                        showVoiceSheet = true 
                                    }
                                )
                            ) { Icon(Icons.Default.PlayCircle, null) }
                            IconButton({ retryDownload() }) { Icon(Icons.Default.CloudDownload, null) }
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
                                Card(modifier = Modifier.padding(4.dp).height(64.dp).clickable { selectedBook = book; step = "chapter"; isSearchVisible = false; prefetchBook(book) }, colors = CardDefaults.cardColors(containerColor = if (progress >= 1f) Color(0xFF9ece6a).copy(alpha = 0.2f) else if (progress > 0f) Color(0xFFe0af68).copy(0.2f) else MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f)), border = if (progress >= 1f) BorderStroke(1.dp, Color(0xFF9ece6a)) else null) { Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Text(book.name, textAlign = TextAlign.Center, style = MaterialTheme.typography.labelMedium) } }
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
                        items(currentChapterContent) { verse ->
                            val vs = verse.number
                            val text = verse.text
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
                                                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.clickable { lexiconWord = word; showLexiconSheet = true; scope.launch { val det = bibleManager.getLexiconDetail(word.strongs); lexiconDetail = if (det.definition.isEmpty()) { bibleManager.scrapeStrong(word.strongs, selectedBook?.name); bibleManager.getLexiconDetail(word.strongs) } else det; if (settings.speakDefinitionsOnTap) viewModel.speak(lexiconDetail.definition) } }) {
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
        ModalBottomSheet(onDismissRequest = { showLexiconSheet = false; lexiconDetail = LexiconEntry("", "Loading...") }) {
            Column(modifier = Modifier.padding(24.dp).fillMaxWidth().verticalScroll(rememberScrollState())) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) { Text(lexiconDetail.lemma.ifEmpty { lexiconWord!!.original }, style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Black, color = MaterialTheme.colorScheme.primary); Text(lexiconWord!!.strongs, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.outline) }
                    IconButton({ viewModel.speak(lexiconDetail.definition) }) { Icon(Icons.AutoMirrored.Filled.VolumeUp, "Speak", tint = MaterialTheme.colorScheme.primary) }
                    IconButton({ bibleManager.saveFavorite(lexiconWord!!.strongs, lexiconDetail.lemma, lexiconDetail.definition) }) { Icon(Icons.Default.Diamond, "Pin", tint = Color(0xFFbb9af7)) }
                }
                HorizontalDivider(modifier = Modifier.padding(vertical = 16.dp), color = MaterialTheme.colorScheme.outlineVariant)
                Text(lexiconDetail.definition, style = MaterialTheme.typography.bodyLarge, lineHeight = 24.sp); Spacer(modifier = Modifier.height(40.dp))
            }
        }
    }

    if (showVoiceSheet) {
        ModalBottomSheet(onDismissRequest = { showVoiceSheet = false }) {
            var useRemote by remember { mutableStateOf(settings.useExperimentalTTS) }
            var selectedVoice by remember { mutableStateOf(settings.selectedVoice) }
            
            Column(modifier = Modifier.padding(24.dp).fillMaxWidth().padding(bottom = 40.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                Text("VOICE SETTINGS", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Black)
                
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    FilterChip(
                        selected = !useRemote,
                        onClick = { useRemote = false; settings.useExperimentalTTS = false },
                        label = { Text("Standard") },
                        leadingIcon = { Icon(Icons.Default.Smartphone, null, Modifier.size(16.dp)) }
                    )
                    FilterChip(
                        selected = useRemote,
                        onClick = { useRemote = true; settings.useExperimentalTTS = true },
                        label = { Text("Neural") },
                        leadingIcon = { Icon(Icons.Default.Cloud, null, Modifier.size(16.dp)) }
                    )
                }

                if (useRemote) {
                    Text("SELECT NEURAL VOICE", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
                    FlowRow(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        viewModel.serverVoices.forEach { voice ->
                            FilterChip(
                                selected = (selectedVoice == voice.key),
                                onClick = { 
                                    selectedVoice = voice.key
                                    settings.selectedVoice = voice.key 
                                },
                                label = { Text(voice.displayName) },
                                enabled = voice.exists
                            )
                        }
                    }
                } else {
                    Text("Using system-native synthesis.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.outline)
                }
                
                Button(onClick = { showVoiceSheet = false }, modifier = Modifier.fillMaxWidth()) {
                    Text("Apply Settings")
                }
            }
        }
    }
}
