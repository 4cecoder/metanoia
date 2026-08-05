package com.bytecats.metanoia.bible

import android.database.sqlite.SQLiteDatabase
import androidx.test.core.app.ApplicationProvider
import com.bytecats.metanoia.bible.BibleDatabase
import com.bytecats.metanoia.models.Verse
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.io.File

@RunWith(RobolectricTestRunner::class)
class DownloadedChaptersTest {

    private lateinit var database: BibleDatabase

    @Before
    fun setup() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        database = BibleDatabase(context)
    }

    @After
    fun teardown() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        File(context.filesDir, "bible.db").delete()
    }

    @Test
    fun testGetDownloadedChapters() {
        val verseDao = database.verse
        
        verseDao.insertVerses("Genesis", 1, listOf(Verse(1, "In the beginning")), "KJV")
        verseDao.insertVerses("Genesis", 3, listOf(Verse(1, "Now the serpent")), "KJV")
        verseDao.insertVerses("Exodus", 1, listOf(Verse(1, "Now these are the names")), "KJV")
        
        val genesisChapters = verseDao.getDownloadedChapters("Genesis")
        assertEquals(setOf(1, 3), genesisChapters)
        
        val exodusChapters = verseDao.getDownloadedChapters("Exodus")
        assertEquals(setOf(1), exodusChapters)
        
        val leviticusChapters = verseDao.getDownloadedChapters("Leviticus")
        assertEquals(emptySet<Int>(), leviticusChapters)
        
    }
}
