import json
import os
import sqlite3
import requests
from bs4 import BeautifulSoup, UnicodeDammit
import sys
import re
import unicodedata

try:
    from tools.bible.scraper_common import fetch_with_retry
except ImportError:
    from scraper_common import fetch_with_retry

_BIBLE_BOOKS_PATH = os.path.join(os.path.dirname(__file__), "..", "bible_books.json")


def load_testament_map():
    """Canonical book->testament map, kept in sync with src/bible_db.zig's
    BIBLE_BOOKS by a Zig regression test (see bible_db.zig test
    "BIBLE_BOOKS testament data matches tools/bible_books.json")."""
    with open(_BIBLE_BOOKS_PATH, "r", encoding="utf-8") as f:
        return {entry["name"]: entry["testament"] for entry in json.load(f)}


def language_prefix(book, testament_map):
    # Old Testament -> Hebrew, everything else (New/EthiopiaExpanded) -> Greek.
    return "H" if testament_map.get(book) == "Old" else "G"


def scrape_interlinear(book, chapter, *, url_template=None, source=None, lang_prefix=None):
    """Scrape one chapter's interlinear table into the `interlinear` table.

    `lang_prefix` overrides the testament-derived H/G Strong's prefix --
    needed for the Septuagint (Apostolic Bible Polyglot), whose Old
    Testament pages carry Greek text and Greek Strong's numbers despite the
    book being "Old" testament. `source` tags which text this chapter came
    from ('MT' Masoretic Hebrew / 'LXX' Septuagint Greek / 'GNT' New
    Testament Greek) so the same (book, chapter, verse, word_index) can
    hold rows from more than one source without INSERT OR REPLACE
    clobbering the others (see idx_interlinear_unique). Defaults preserve
    the original MT/GNT-only behavior for existing callers.
    """
    prefix = lang_prefix if lang_prefix is not None else language_prefix(book, load_testament_map())
    if source is None:
        source = "MT" if prefix == "H" else "GNT"
    if url_template is None:
        url_template = "https://biblehub.com/interlinear/{book}/{chapter}.htm"

    # BibleHub's URL slugs put an underscore after a leading ordinal digit
    # for numbered books ("1_corinthians", "2_kings", "3_john", ...) but
    # nowhere else -- "1corinthians" 404s. Verified against the live site
    # for every numbered book in BIBLE_BOOKS (1-3 Samuel/Kings/Chronicles/
    # Corinthians/Thessalonians/Timothy/Peter/John).
    book_url = book.lower().replace(" ", "")
    if book_url[:1].isdigit():
        book_url = book_url[0] + "_" + book_url[1:]
    url = url_template.format(book=book_url, chapter=chapter)
    print(f"Scraping: {url} (Prefix: {prefix}, Source: {source})")

    headers = {'User-Agent': 'Mozilla/5.0'}
    try:
        response = fetch_with_retry(url, headers=headers, timeout=15)
        response.raise_for_status()
    except requests.RequestException as e:
        print(f"Failed to fetch {url}: {e}")
        sys.exit(1)

    dammit = UnicodeDammit(response.content, ["utf-8", "windows-1253", "iso-8859-7"])
    soup = BeautifulSoup(dammit.unicode_markup, 'html.parser')

    conn = sqlite3.connect("data/bible.db")
    cursor = conn.cursor()

    current_verse = 0
    verse_word_index = 0

    for table in soup.find_all("table", class_=["tablefloat", "tablefloatheb"]):
        # Verse Detection
        v_span = table.find("span", class_=["reftop3", "reftop"])
        if v_span:
            # Standard interlinear pages render a bare verse number
            # ("1", "2", ...); the Apostolic Bible Polyglot (Septuagint)
            # pages render "chapter:verse" ("1:1", "1:10", ...) -- take
            # only the part after the last colon, else digit-concatenation
            # mangles multi-digit verses (e.g. "1:10" -> "110").
            ref_text = v_span.get_text().strip()
            verse_part = ref_text.rsplit(":", 1)[-1]
            v_txt = "".join(filter(str.isdigit, verse_part))
            if v_txt:
                new_v = int(v_txt)
                if new_v != current_verse:
                    current_verse = new_v
                    verse_word_index = 0 # Reset index for new verse

        if current_verse == 0: continue

        orig = table.find("span", class_=["greek", "heb", "hebrew"])
        if orig:
            text = unicodedata.normalize('NFC', orig.get_text().strip())
            
            s_span = table.find("span", class_=["pos", "strongs"])
            strongs = ""
            if s_span:
                s_link = s_span.find("a")
                raw_s = s_link.get_text().strip() if s_link else s_span.get_text().strip()
                # Ensure prefix is added if missing
                if not raw_s.startswith(("G", "H")):
                    strongs = f"{prefix}{''.join(filter(str.isdigit, raw_s))}"
                else:
                    strongs = raw_s
            
            eng = table.find("span", class_="eng")
            trans = eng.get_text().strip() if eng else ""

            m_spans = table.find_all("span", class_=["strongsnt2", "strongsnt"])
            morph = ""
            for ms in m_spans:
                if ms.find("a", href=re.compile(r"/grammar/")):
                    morph = ms.get_text().strip()
                    break

            # Use verse_word_index instead of global words_processed
            cursor.execute(
                "INSERT OR REPLACE INTO interlinear (book, chapter, verse, word_index, original_text, translation, strongs, morphology, source) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (book, chapter, current_verse, verse_word_index, text, trans, strongs, morph, source)
            )
            verse_word_index += 1

    conn.commit()
    conn.close()
    print(f"Done. Processed interlinear for {book} {chapter}.")

if __name__ == "__main__":
    scrape_interlinear(sys.argv[1], sys.argv[2])
