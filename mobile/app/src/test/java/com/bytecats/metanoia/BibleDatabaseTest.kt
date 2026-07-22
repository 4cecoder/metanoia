package com.bytecats.metanoia

import android.database.sqlite.SQLiteDatabase
import com.bytecats.metanoia.bible.BibleDatabase
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Regression coverage for the "clean install: bible.db never gets created"
 * bug — SQLiteDatabase.openDatabase(path, null, OPEN_READWRITE) throws
 * SQLITE_CANTOPEN (error 14) if the file doesn't exist yet; it does NOT
 * create it without CREATE_IF_NECESSARY. BibleDatabase's init() (and every
 * write method, e.g. insertVerses/saveNote/setHighlight) opened for write
 * via that flag alone, so on a fresh install every write silently failed
 * and the db file was never created, which is exactly what surfaced as
 * "Couldn't download interlinear for Genesis 1: ... SQLITE_CANTOPEN ...
 * no such file or directory" on a real device.
 */
class BibleDatabaseTest {

    @Test
    fun writeFlagsIncludeCreateIfNecessary() {
        val flags = BibleDatabase.openFlags(readOnly = false)
        // Note: SQLiteDatabase.OPEN_READWRITE is 0 on Android (read-write is
        // the absence of the OPEN_READONLY bit, not a separate flag), so the
        // only meaningful thing to assert here is the CREATE_IF_NECESSARY bit.
        assertTrue(
            "write-mode flags must include CREATE_IF_NECESSARY or a clean install can never create bible.db",
            (flags and SQLiteDatabase.CREATE_IF_NECESSARY) != 0
        )
        assertTrue((flags and SQLiteDatabase.OPEN_READONLY) == 0)
    }

    @Test
    fun readOnlyFlagsDoNotRequestCreation() {
        val flags = BibleDatabase.openFlags(readOnly = true)
        assertEquals(SQLiteDatabase.OPEN_READONLY, flags)
        assertTrue((flags and SQLiteDatabase.CREATE_IF_NECESSARY) == 0)
    }
}
