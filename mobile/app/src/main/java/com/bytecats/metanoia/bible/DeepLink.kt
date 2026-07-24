package com.bytecats.metanoia.bible

import android.net.Uri
import com.bytecats.metanoia.models.BIBLE_ABBREVIATIONS
import com.bytecats.metanoia.models.BOOKS

/**
 * A resolved deep-link target: a specific book/chapter, optionally a verse.
 * `book` is always the canonical BOOKS entry's exact name (e.g. "SongofSolomon",
 * "1Samuel") — never the raw path segment from the incoming URI.
 */
data class VerseReference(val book: String, val chapter: Int, val verse: Int?)

/**
 * Parses incoming deep links for a specific Bible passage. Two supported
 * forms, both with the same path shape (/bible/<book>/<chapter>[/<verse>]):
 *
 *   metanoia://bible/<book>/<chapter>[/<verse>]        (custom scheme, works
 *                                                        immediately, no
 *                                                        verification needed)
 *   https://<any-host>/bible/<book>/<chapter>[/<verse>] (Android App Link —
 *                                                        host is intentionally
 *                                                        NOT checked here, see
 *                                                        docs/ANDROID_DEEP_LINKS.md
 *                                                        for why and what
 *                                                        still needs to be
 *                                                        done for real
 *                                                        verified App Links)
 *
 * <book> may be a canonical BOOKS name (case-insensitive) or a
 * BIBLE_ABBREVIATIONS key (e.g. "jn", "1sam") — never both silently resolving
 * to different books, since BOOKS names take priority and abbreviations only
 * apply to the Old/New Testament books that map has entries for (see that
 * map's own comment for why the Ethiopian-canon books aren't in it yet).
 *
 * `parseParts` is the actual (pure, no-Android-dependency) logic, taking
 * plain strings instead of a real android.net.Uri so it's directly unit
 * testable on the JVM without Robolectric (Uri.parse/getPathSegments are
 * stubbed methods otherwise) — the same split this codebase already uses
 * elsewhere (e.g. BibleScraper's injectable Call.Factory). `parse(Uri)` is
 * the thin, untested-by-design wrapper real Android code calls.
 *
 * Returns null for anything malformed (wrong scheme/path shape, unresolvable
 * book, non-numeric or out-of-range chapter/verse) — never throws. This is
 * parsing untrusted input from other apps or the web; a bad link should be a
 * silent no-op (or a caller-shown error), never a crash.
 */
object DeepLink {

    fun parse(uri: Uri): VerseReference? =
        parseParts(uri.scheme, uri.host, uri.pathSegments?.toList() ?: emptyList())

    fun parseParts(scheme: String?, host: String?, pathSegments: List<String>): VerseReference? {
        // Custom-scheme URIs (metanoia://bible/...) put "bible" in the host,
        // not the path -- Uri parses "bible" as the authority there, so the
        // real path segments start at book/chapter/verse directly. https
        // URIs put "bible" as the first path segment instead. Normalize both
        // to the same book/chapter/verse segment list.
        val bookChapterVerse = when {
            scheme.equals("metanoia", ignoreCase = true) && host.equals("bible", ignoreCase = true) ->
                pathSegments
            (scheme.equals("https", ignoreCase = true) || scheme.equals("http", ignoreCase = true)) &&
                pathSegments.firstOrNull().equals("bible", ignoreCase = true) ->
                pathSegments.drop(1)
            else -> return null
        }

        val bookSegment = bookChapterVerse.getOrNull(0) ?: return null
        val chapterSegment = bookChapterVerse.getOrNull(1) ?: return null
        val verseSegment = bookChapterVerse.getOrNull(2)

        val book = resolveBook(bookSegment) ?: return null

        val chapter = chapterSegment.toIntOrNull() ?: return null
        if (chapter < 1 || chapter > book.chapters) return null

        val verse = verseSegment?.let { it.toIntOrNull() }
        if (verseSegment != null && verse == null) return null // present but not a number -> malformed
        if (verse != null && verse < 1) return null

        return VerseReference(book.name, chapter, verse)
    }

    /** Case-insensitive canonical-name match first, then abbreviation lookup. */
    private fun resolveBook(segment: String) =
        BOOKS.find { it.name.equals(segment, ignoreCase = true) }
            ?: BIBLE_ABBREVIATIONS[segment.lowercase()]?.let { canonical -> BOOKS.find { it.name == canonical } }
}
