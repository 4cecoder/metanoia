package com.bytecats.metanoia.ui.screens

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.bytecats.metanoia.models.*
import com.bytecats.metanoia.ui.components.bible.*
import com.bytecats.metanoia.ui.components.HighlightedText
import com.bytecats.metanoia.viewmodel.MainViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
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
    var readCompletionMap by remember { mutableStateOf(bibleManager.getReadCompletion()) }
    val snackbarHostState = remember { SnackbarHostState() }
    val scrapeError by bibleManager.scrapeError.collectAsState()

    // ------------------------------------------------------------------
    // Helper functions
    // ------------------------------------------------------------------

    fun prefetchBook(book: BibleBook) {
        if ((completionMap[book.name] ?: 0f) >= 1f) return
        scope.launch(Dispatchers.IO) {
            for (ch in 1..book.chapters) {
                try { bibleManager.fetchChapter(book.name, ch, settings.bibleGatewayVersion) }
                catch (_: Exception) { }
            }
            completionMap = bibleManager.getBookCompletion()
        }
    }

    fun retryDownload() {
        val b = selectedBook ?: return
        scope.launch {
            bibleManager.scrapeChapter(b.name, selectedChapter, settings.bibleGatewayVersion)
            bibleManager.scrapeInterlinear(b.name, selectedChapter)
            currentChapterContent = bibleManager.getChapter(b.name, selectedChapter)
            highlights = bibleManager.getHighlights(b.name, selectedChapter)
        }
    }

    fun navigate(dir: Int) {
        val b = selectedBook ?: return
        var nCh = selectedChapter + dir; var nB = b
        if (nCh > b.chapters) {
            val idx = bibleManager.books.indexOf(b)
            if (idx < bibleManager.books.size - 1) { nB = bibleManager.books[idx + 1]; nCh = 1 } else return
        } else if (nCh < 1) {
            val idx = bibleManager.books.indexOf(b)
            if (idx > 0) { nB = bibleManager.books[idx - 1]; nCh = nB.chapters } else return
        }
        viewModel.stopNarration(); selectedBook = nB; selectedChapter = nCh; expandedVerses = emptySet()
        scope.launch {
            val c = withContext(Dispatchers.IO) { bibleManager.getChapter(nB.name, nCh) }
            val hl = withContext(Dispatchers.IO) { bibleManager.getHighlights(nB.name, nCh) }
            currentChapterContent = c; highlights = hl; listState.scrollToItem(0)
        }
    }

    // ------------------------------------------------------------------
    // Side effects
    // ------------------------------------------------------------------

    LaunchedEffect(scrapeError) {
        scrapeError?.let {
            val result = snackbarHostState.showSnackbar(it, actionLabel = "Retry", withDismissAction = true)
            if (result == SnackbarResult.ActionPerformed) retryDownload()
        }
    }

    LaunchedEffect(narration.currentVerse) {
        if (narration.isPlaying && narration.currentVerse != -1) {
            val idx = currentChapterContent.indexOfFirst { it.number == narration.currentVerse }
            if (idx != -1) listState.animateScrollToItem(idx)
        }
    }

    LaunchedEffect(viewModel.pendingDeepLink) {
        val target = viewModel.pendingDeepLink ?: return@LaunchedEffect
        val book = bibleManager.books.find { it.name == target.book }
        if (book == null) { viewModel.pendingDeepLink = null; return@LaunchedEffect }
        viewModel.stopNarration()
        selectedBook = book; selectedChapter = target.chapter; isSearchVisible = false
        val content = withContext(Dispatchers.IO) { bibleManager.fetchChapter(book.name, target.chapter, settings.bibleGatewayVersion) }
        val hl = withContext(Dispatchers.IO) { bibleManager.getHighlights(book.name, target.chapter) }
        currentChapterContent = content; highlights = hl; step = "read"
        viewModel.pendingDeepLink = null
        target.verse?.let { v ->
            val idx = content.indexOfFirst { it.number == v }
            if (idx != -1) listState.scrollToItem(idx)
        }
    }

    LaunchedEffect(selectedBook, selectedChapter, step) {
        if (step != "read") return@LaunchedEffect
        val b = selectedBook ?: return@LaunchedEffect
        withContext(Dispatchers.IO) { bibleManager.recordChapterRead(b.name, selectedChapter) }
        readCompletionMap = bibleManager.getReadCompletion()
    }

    // ------------------------------------------------------------------
    // UI
    // ------------------------------------------------------------------

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
                                border = null,
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
                            if (narration.isPlaying) {
                                IconButton({ viewModel.stopNarration() }) { Icon(Icons.Default.StopCircle, null, tint = Color.Red) }
                            } else {
                                IconButton(
                                    onClick = { viewModel.startChapterNarration(currentChapterContent) },
                                    modifier = Modifier.combinedClickable(
                                        onClick = { viewModel.startChapterNarration(currentChapterContent) },
                                        onLongClick = {
                                            haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                            showVoiceSheet = true
                                        }
                                    )
                                ) { Icon(Icons.Default.PlayCircle, null) }
                            }
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
                                    modifier = Modifier.combinedClickable(
                                        onClick = {
                                            selectedBook = bibleManager.books.find { it.name == res.book }
                                            selectedChapter = res.chapter
                                            currentChapterContent = bibleManager.getChapter(res.book, res.chapter)
                                            highlights = bibleManager.getHighlights(res.book, res.chapter)
                                            searchQuery = ""; isSearchVisible = false; step = "read"
                                        }
                                    )
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

        Column(
            modifier = Modifier
                .padding(innerPadding)
                .fillMaxSize()
                .pointerInput(Unit) {
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
                }
        ) {
            when (step) {
                "book" -> {
                    BookGrid(
                        books = bibleManager.books,
                        completionMap = completionMap,
                        readCompletionMap = readCompletionMap,
                        showEthiopianCanon = settings.showEthiopianCanon,
                        showApocrypha = settings.showApocrypha,
                        onBookSelected = { book ->
                            selectedBook = book; step = "chapter"; isSearchVisible = false
                            prefetchBook(book)
                        }
                    )
                }
                "chapter" -> {
                    ChapterGrid(
                        chapterCount = selectedBook?.chapters ?: 1,
                        onChapterSelected = { ch ->
                            selectedChapter = ch
                            currentChapterContent = bibleManager.getChapter(selectedBook!!.name, ch)
                            highlights = bibleManager.getHighlights(selectedBook!!.name, ch)
                            step = "read"
                        }
                    )
                }
                "read" -> {
                    LazyColumn(
                        state = listState,
                        modifier = Modifier.fillMaxSize().padding(horizontal = 16.dp)
                    ) {
                        items(currentChapterContent) { verse ->
                            val vs = verse.number
                            val expanded = expandedVerses.contains(vs)
                            VerseItem(
                                verse = verse,
                                isCurrent = narration.isPlaying && narration.currentVerse == vs,
                                isExpanded = expanded,
                                highlight = highlights[vs] ?: 0,
                                hasNotes = bibleManager.getNotes(selectedBook!!.name, selectedChapter, vs).isNotEmpty(),
                                englishFontSize = settings.englishFontSize,
                                ancientFontSize = settings.ancientFontSize,
                                interlinearWords = interlinearData[vs] ?: emptyList(),
                                onSpeak = { viewModel.speak(it) },
                                onToggleInterlinear = {
                                    expandedVerses = if (expanded) expandedVerses - vs else expandedVerses + vs
                                    if (!expanded && !interlinearData.containsKey(vs)) {
                                        interlinearData = interlinearData + (vs to bibleManager.getInterlinear(selectedBook!!.name, selectedChapter, vs))
                                    }
                                },
                                onLongPress = {
                                    studyVerse = vs; showStudySheet = true
                                },
                                onWordClick = { word ->
                                    lexiconWord = word; showLexiconSheet = true
                                    scope.launch {
                                        val det = bibleManager.getLexiconDetail(word.strongs)
                                        lexiconDetail = if (det.definition.isEmpty()) {
                                            bibleManager.scrapeStrong(word.strongs, selectedBook?.name)
                                            bibleManager.getLexiconDetail(word.strongs)
                                        } else det
                                        if (settings.speakDefinitionsOnTap) viewModel.speak(lexiconDetail.definition)
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    // Bottom sheets
    if (showStudySheet && studyVerse != null) {
        StudySheet(
            bookName = selectedBook?.name ?: "",
            chapter = selectedChapter,
            verse = studyVerse!!,
            notes = bibleManager.getNotes(selectedBook!!.name, selectedChapter, studyVerse!!),
            onDismiss = { showStudySheet = false },
            onHighlight = { color ->
                bibleManager.setHighlight(selectedBook!!.name, selectedChapter, studyVerse!!, color)
                highlights = bibleManager.getHighlights(selectedBook!!.name, selectedChapter)
            },
            onSaveNote = { content ->
                bibleManager.saveNote(selectedBook!!.name, selectedChapter, studyVerse!!, content)
            }
        )
    }

    if (showLexiconSheet && lexiconWord != null) {
        LexiconSheet(
            word = lexiconWord!!,
            detail = lexiconDetail,
            onDismiss = { showLexiconSheet = false; lexiconDetail = LexiconEntry("", "Loading...") },
            onSpeak = { viewModel.speak(it) },
            onFavorite = { strongs, lemma, def ->
                bibleManager.saveFavorite(strongs, lemma, def)
            }
        )
    }

    if (showVoiceSheet) {
        VoiceSheet(
            serverVoices = viewModel.serverVoices,
            initialUseRemote = settings.useExperimentalTTS,
            initialVoice = settings.selectedVoice,
            onDismiss = { showVoiceSheet = false },
            onToggleRemote = { settings.useExperimentalTTS = it },
            onSelectVoice = { settings.selectedVoice = it }
        )
    }
}
