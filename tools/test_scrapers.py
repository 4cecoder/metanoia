"""Tests for the BibleHub scrapers (interlinear_scraper.py, lexicon_scraper.py)
and their shared retry helper (scraper_common.py).

Run with: .venv/bin/pytest tools/test_scrapers.py

No real network calls are made -- requests.get is always mocked via
unittest.mock. No real `data/bible.db` is touched -- sqlite3.connect is
mocked or pointed at a throwaway temp file.
"""

import os
import sqlite3
import sys
import tempfile
import unittest
from unittest.mock import patch

import requests

sys.path.insert(0, os.path.dirname(__file__))

import scraper_common
import interlinear_scraper
import lexicon_scraper
from scraper_common import fetch_with_retry


class FakeResponse:
    """Minimal stand-in for requests.Response."""

    def __init__(self, status_code, content=b""):
        self.status_code = status_code
        self.content = content
        self.text = content.decode("utf-8", "ignore") if isinstance(content, bytes) else content

    def raise_for_status(self):
        if self.status_code >= 400:
            raise requests.HTTPError(f"{self.status_code} error")


# ---------------------------------------------------------------------------
# fetch_with_retry (scraper_common.py)
# ---------------------------------------------------------------------------

class TestFetchWithRetry(unittest.TestCase):
    def test_succeeds_first_try_no_retry(self):
        with patch("scraper_common.requests.get", return_value=FakeResponse(200)) as mock_get, \
             patch("scraper_common.time.sleep") as mock_sleep:
            resp = fetch_with_retry("http://example.com", attempts=3, backoff=0.01)

        self.assertEqual(resp.status_code, 200)
        mock_get.assert_called_once()
        mock_sleep.assert_not_called()

    def test_retries_on_connection_error_then_succeeds(self):
        responses = [requests.ConnectionError("boom"), FakeResponse(200)]

        def side_effect(*_a, **_kw):
            r = responses.pop(0)
            if isinstance(r, Exception):
                raise r
            return r

        with patch("scraper_common.requests.get", side_effect=side_effect) as mock_get, \
             patch("scraper_common.time.sleep") as mock_sleep:
            resp = fetch_with_retry("http://example.com", attempts=3, backoff=0.01)

        self.assertEqual(resp.status_code, 200)
        self.assertEqual(mock_get.call_count, 2)
        mock_sleep.assert_called_once()

    def test_retries_on_timeout_then_succeeds(self):
        responses = [requests.Timeout("slow"), FakeResponse(200)]

        def side_effect(*_a, **_kw):
            r = responses.pop(0)
            if isinstance(r, Exception):
                raise r
            return r

        with patch("scraper_common.requests.get", side_effect=side_effect) as mock_get, \
             patch("scraper_common.time.sleep"):
            resp = fetch_with_retry("http://example.com", attempts=3, backoff=0.01)

        self.assertEqual(resp.status_code, 200)
        self.assertEqual(mock_get.call_count, 2)

    def test_retries_on_5xx_then_succeeds(self):
        responses = [FakeResponse(503), FakeResponse(200)]

        with patch("scraper_common.requests.get", side_effect=responses) as mock_get, \
             patch("scraper_common.time.sleep") as mock_sleep:
            resp = fetch_with_retry("http://example.com", attempts=3, backoff=0.01)

        self.assertEqual(resp.status_code, 200)
        self.assertEqual(mock_get.call_count, 2)
        mock_sleep.assert_called_once()

    def test_exhausting_retries_on_5xx_returns_last_response(self):
        with patch("scraper_common.requests.get", return_value=FakeResponse(500)) as mock_get, \
             patch("scraper_common.time.sleep"):
            resp = fetch_with_retry("http://example.com", attempts=3, backoff=0.01)

        self.assertEqual(resp.status_code, 500)
        self.assertEqual(mock_get.call_count, 3)

    def test_exhausting_retries_on_connection_error_raises(self):
        with patch("scraper_common.requests.get", side_effect=requests.ConnectionError("down")) as mock_get, \
             patch("scraper_common.time.sleep"):
            with self.assertRaises(requests.ConnectionError):
                fetch_with_retry("http://example.com", attempts=3, backoff=0.01)

        self.assertEqual(mock_get.call_count, 3)

    def test_4xx_is_not_retried(self):
        """A 404 (page doesn't exist -- e.g. a deuterocanonical book BibleHub
        has no interlinear page for) must return immediately, not retry."""
        with patch("scraper_common.requests.get", return_value=FakeResponse(404)) as mock_get, \
             patch("scraper_common.time.sleep") as mock_sleep:
            resp = fetch_with_retry("http://example.com", attempts=3, backoff=0.01)

        self.assertEqual(resp.status_code, 404)
        mock_get.assert_called_once()
        mock_sleep.assert_not_called()

    def test_backoff_delays_double_each_attempt(self):
        with patch("scraper_common.requests.get", return_value=FakeResponse(500)), \
             patch("scraper_common.time.sleep") as mock_sleep:
            fetch_with_retry("http://example.com", attempts=3, backoff=1.0)

        mock_sleep.assert_any_call(1.0)
        mock_sleep.assert_any_call(2.0)


# ---------------------------------------------------------------------------
# interlinear_scraper.py integration points
# ---------------------------------------------------------------------------

class TestInterlinearScraperLanguagePrefix(unittest.TestCase):
    """Confirms the language-prefix lookup still resolves correctly through
    tools/bible_books.json -- not re-testing that data, just the integration."""

    def test_old_testament_book_is_hebrew(self):
        tmap = interlinear_scraper.load_testament_map()
        self.assertEqual(interlinear_scraper.language_prefix("Genesis", tmap), "H")

    def test_new_testament_book_is_greek(self):
        tmap = interlinear_scraper.load_testament_map()
        self.assertEqual(interlinear_scraper.language_prefix("John", tmap), "G")

    def test_unknown_book_defaults_to_greek(self):
        tmap = interlinear_scraper.load_testament_map()
        self.assertEqual(interlinear_scraper.language_prefix("NotABook", tmap), "G")


class TestInterlinearScraperUsesRetry(unittest.TestCase):
    """Confirms scrape_interlinear() goes through fetch_with_retry (so it
    benefits from the retry/backoff behavior) and still exits non-zero when
    the fetch ultimately fails, per the earlier fix that scraper_client.zig
    depends on."""

    def _fresh_db(self):
        fd, path = tempfile.mkstemp(suffix=".db")
        os.close(fd)
        conn = sqlite3.connect(path)
        conn.execute(
            "CREATE TABLE interlinear (id INTEGER PRIMARY KEY, book TEXT, chapter INTEGER, "
            "verse INTEGER, word_index INTEGER, original_text TEXT, translation TEXT, "
            "strongs TEXT, morphology TEXT)"
        )
        conn.commit()
        conn.close()
        return path

    def test_successful_fetch_uses_fetch_with_retry_with_correct_url(self):
        db_path = self._fresh_db()
        empty_page = FakeResponse(200, content=b"<html><body></body></html>")
        try:
            with patch("interlinear_scraper.fetch_with_retry", return_value=empty_page) as mock_fetch, \
                 patch("interlinear_scraper.sqlite3.connect", return_value=sqlite3.connect(db_path)):
                interlinear_scraper.scrape_interlinear("Genesis", 1)

            self.assertEqual(mock_fetch.call_count, 1)
            called_url = mock_fetch.call_args[0][0]
            self.assertIn("biblehub.com/interlinear/genesis/1.htm", called_url)
        finally:
            os.remove(db_path)

    def test_exhausted_retries_exit_nonzero(self):
        with patch("interlinear_scraper.fetch_with_retry", side_effect=requests.ConnectionError("down")):
            with self.assertRaises(SystemExit) as ctx:
                interlinear_scraper.scrape_interlinear("Genesis", 1)
        self.assertNotEqual(ctx.exception.code, 0)


# ---------------------------------------------------------------------------
# lexicon_scraper.py scoping
# ---------------------------------------------------------------------------

class TestLexiconScoping(unittest.TestCase):
    def setUp(self):
        fd, self.db_path = tempfile.mkstemp(suffix=".db")
        os.close(fd)
        self.conn = sqlite3.connect(self.db_path)
        self.conn.execute(
            "CREATE TABLE interlinear (id INTEGER PRIMARY KEY, book TEXT, chapter INTEGER, "
            "verse INTEGER, word_index INTEGER, original_text TEXT, translation TEXT, "
            "strongs TEXT, morphology TEXT)"
        )
        self.conn.execute(
            "CREATE TABLE lexicon (strongs TEXT PRIMARY KEY, language TEXT, lemma TEXT, "
            "transliteration TEXT, definition TEXT, usage TEXT)"
        )
        self.conn.executemany(
            "INSERT INTO interlinear (book, chapter, verse, word_index, original_text, "
            "translation, strongs, morphology) VALUES (?,?,?,?,?,?,?,?)",
            [
                ("John", 1, 1, 0, "a", "a", "G100", ""),
                ("John", 2, 1, 0, "b", "b", "G200", ""),
                ("Genesis", 1, 1, 0, "c", "c", "H300", ""),
            ],
        )
        self.conn.commit()

    def tearDown(self):
        self.conn.close()
        os.remove(self.db_path)

    def _run(self, book=None, chapter=None):
        fetched = []

        def fake_scrape_strongs(num, lang):
            fetched.append(f"{'G' if lang == 'greek' else 'H'}{num}")
            return {
                "strongs": f"{'G' if lang == 'greek' else 'H'}{num}",
                "language": lang,
                "lemma": "",
                "translit": "",
                "definition": "d",
                "usage": "",
            }

        with patch("lexicon_scraper.sqlite3.connect", return_value=self.conn), \
             patch("lexicon_scraper.scrape_strongs", side_effect=fake_scrape_strongs), \
             patch("lexicon_scraper.time.sleep"):
            if book is not None:
                lexicon_scraper.cache_lexicon_from_db(book, chapter)
            else:
                lexicon_scraper.cache_lexicon_from_db()

        return fetched

    def test_scoped_to_book_and_chapter_only_fetches_that_chapters_strongs(self):
        fetched = self._run("John", 1)
        self.assertEqual(fetched, ["G100"])

    def test_unscoped_fetches_all_strongs_in_db(self):
        fetched = self._run()
        self.assertEqual(sorted(fetched), ["G100", "G200", "H300"])

    def test_scoped_to_chapter_with_no_new_strongs_fetches_nothing(self):
        fetched = self._run("John", 99)
        self.assertEqual(fetched, [])

    def test_argv_parsing_scopes_when_book_and_chapter_given(self):
        book, chapter = lexicon_scraper._parse_args(["lexicon_scraper.py", "John", "1"])
        self.assertEqual((book, chapter), ("John", 1))

    def test_argv_parsing_defaults_to_whole_db_when_no_args(self):
        book, chapter = lexicon_scraper._parse_args(["lexicon_scraper.py"])
        self.assertEqual((book, chapter), (None, None))


if __name__ == "__main__":
    unittest.main()
