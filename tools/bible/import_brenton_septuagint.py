"""Import Sir Lancelot Brenton's 1851 English translation of the
Septuagint (public domain) into the `verses` table as version 'LXXE', so
the English reading pane can match the Septuagint-Greek interlinear
(source 'LXX' -- see migrate_add_interlinear_source.py) instead of only
ever offering NKJV (translated from the Hebrew Masoretic Text).

Source: eBible.org's per-chapter HTML distribution of the Brenton text
(https://ebible.org/eng-Brenton/), downloaded as a single zip
(https://ebible.org/Scriptures/eng-Brenton_html.zip) -- no per-chapter
scraping/rate-limiting needed, it's one static archive covering the whole
translation including the Apocrypha/deuterocanon in one shot.

Usage:
    uv run python3 tools/bible/import_brenton_septuagint.py [path-to-zip]

If the zip isn't already downloaded, this fetches it once to a temp path.
"""

import os
import re
import sqlite3
import sys
import tempfile
import zipfile

import requests
from bs4 import BeautifulSoup

_DB_PATH = os.path.join(os.path.dirname(__file__), "..", "..", "data", "bible.db")
_ZIP_URL = "https://ebible.org/Scriptures/eng-Brenton_html.zip"
_VERSION = "LXXE"

# Our BIBLE_BOOKS name -> (eBible/USFM 3-letter code, chapter count we
# expect/accept). Only books actually present in both our canon and this
# archive are listed. Brenton is Old Testament (LXX) only -- there is no
# New Testament content to import.
BOOK_MAP = {
    "Genesis": ("GEN", 50), "Exodus": ("EXO", 40), "Leviticus": ("LEV", 27),
    "Numbers": ("NUM", 36), "Deuteronomy": ("DEU", 34), "Joshua": ("JOS", 24),
    "Judges": ("JDG", 21), "Ruth": ("RUT", 4), "1Samuel": ("1SA", 31),
    "2Samuel": ("2SA", 24), "1Kings": ("1KI", 22), "2Kings": ("2KI", 25),
    "1Chronicles": ("1CH", 29), "2Chronicles": ("2CH", 36), "Ezra": ("EZR", 10),
    "Nehemiah": ("NEH", 13), "Esther": ("ESG", 10), "Job": ("JOB", 42),
    "Psalms": ("PSA", 150),  # archive also has Psalm 151 (PSA151); skipped --
    # our BIBLE_BOOKS registers Psalms as 150 chapters and other code (chapter
    # nav bounds) assumes that, so importing a 151st chapter would silently
    # create an unreachable orphan row rather than a real fix.
    "Proverbs": ("PRO", 31), "Ecclesiastes": ("ECC", 12),
    "SongofSolomon": ("SNG", 8), "Isaiah": ("ISA", 66), "Jeremiah": ("JER", 52),
    "Lamentations": ("LAM", 5), "Ezekiel": ("EZK", 48), "Daniel": ("DAG", 12),
    "Hosea": ("HOS", 14), "Joel": ("JOL", 3), "Amos": ("AMO", 9),
    "Obadiah": ("OBA", 1), "Jonah": ("JON", 4), "Micah": ("MIC", 7),
    "Nahum": ("NAM", 3), "Habakkuk": ("HAB", 3), "Zephaniah": ("ZEP", 3),
    "Haggai": ("HAG", 2), "Zechariah": ("ZEC", 14), "Malachi": ("MAL", 3),
    # Deuterocanon already registered in BIBLE_BOOKS:
    "Tobit": ("TOB", 14), "Judith": ("JDT", 16), "Wisdom": ("WIS", 19),
    "Sirach": ("SIR", 51),
    # Newly added (see main.zig / bible_db.zig BIBLE_BOOKS additions):
    "Baruch": ("BAR", 5), "1Maccabees": ("1MA", 16), "2Maccabees": ("2MA", 15),
}


def parse_chapter(html: str) -> dict[int, str]:
    """Returns {verse_number: text} for one eBible chapter HTML file."""
    soup = BeautifulSoup(html, "html.parser")
    main = soup.find("div", class_="main")
    if main is None:
        return {}

    # Footnote markers ("*", nested popup text) aren't part of the verse text.
    for note in main.find_all("a", class_="notemark"):
        note.decompose()

    # Replace each verse-number span's own displayed text (e.g. "12\xa0")
    # with a NUL-delimited sentinel carrying just the verse number, so a
    # single main.get_text() call (which correctly flattens the nested
    # inline <span class='sc'>/<span class='add'> styling spans) can be
    # split back into (verse_number, verse_text) pairs.
    for span in main.find_all("span", class_="verse"):
        vnum = span.get("id", "")[1:]
        span.string = f"\x00{vnum}\x00"

    parts = main.get_text().split("\x00")
    verses = {}
    for i in range(1, len(parts) - 1, 2):
        vnum = int(parts[i])
        vtext = re.sub(r"\s+", " ", parts[i + 1]).strip()
        if vtext:
            verses[vnum] = vtext
    return verses


def ensure_zip(path: str | None) -> str:
    if path and os.path.exists(path):
        return path
    tmp_path = os.path.join(tempfile.gettempdir(), "eng-Brenton_html.zip")
    if not os.path.exists(tmp_path):
        print(f"Downloading {_ZIP_URL} ...")
        resp = requests.get(_ZIP_URL, headers={"User-Agent": "Mozilla/5.0"}, timeout=60)
        resp.raise_for_status()
        with open(tmp_path, "wb") as f:
            f.write(resp.content)
    return tmp_path


def import_brenton(zip_path: str | None = None):
    zip_path = ensure_zip(zip_path)
    conn = sqlite3.connect(_DB_PATH)
    cursor = conn.cursor()

    total_verses = 0
    with zipfile.ZipFile(zip_path) as z:
        names = set(z.namelist())
        for book, (code, chapters) in BOOK_MAP.items():
            book_verses = 0
            for chapter in range(1, chapters + 1):
                # Every book zero-pads chapter numbers to 2 digits (PSA01,
                # GEN01, ...) except Psalms, which pads to 3 (PSA001) --
                # try both rather than special-casing the book by name, in
                # case another book turns out to have the same quirk.
                fname = f"{code}{chapter:02d}.htm"
                if fname not in names:
                    fname3 = f"{code}{chapter:03d}.htm"
                    if fname3 in names:
                        fname = fname3
                    else:
                        print(f"  missing {fname} in archive -- skipping {book} {chapter}")
                        continue
                html = z.read(fname).decode("utf-8")
                verses = parse_chapter(html)
                cursor.executemany(
                    "INSERT OR REPLACE INTO verses (book, chapter, verse, text, version) VALUES (?, ?, ?, ?, ?)",
                    [(book, chapter, vn, text, _VERSION) for vn, text in verses.items()],
                )
                book_verses += len(verses)
            conn.commit()
            print(f"{book}: {book_verses} verses")
            total_verses += book_verses

    cursor.execute(
        "INSERT OR IGNORE INTO versions (slug, name) VALUES (?, ?)",
        (_VERSION, "Brenton's English Septuagint (1851)"),
    )
    conn.commit()
    conn.close()
    print(f"\nDone. {total_verses} total LXXE verses imported.")


if __name__ == "__main__":
    import_brenton(sys.argv[1] if len(sys.argv) > 1 else None)
