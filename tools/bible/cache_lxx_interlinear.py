"""Cache the Septuagint (LXX) Greek Old Testament interlinear, tagged
source='LXX', from BibleHub's Apostolic Bible Polyglot pages
(biblehub.com/interlinear/apostolic/{book}/{chapter}.htm) -- same page
template/CSS classes as the standard interlinear (tablefloat/strongs/
greek/reftop), just Greek text+Strong's numbers for Old Testament books.

This is additive: it never touches the existing Masoretic Hebrew (source
'MT') rows for these same verses (see migrate_add_interlinear_source.py
and idx_interlinear_unique).

Not every book in our Old Testament canon has an Apostolic Bible Polyglot
page -- it covers the standard LXX corpus (39 protocanonical + the usual
Greek deuterocanonicals) but not the Ethiopian-only expansions (Enoch,
Jubilees, Meqabyan, Tegsas, ...). Missing chapters 404; those are skipped
and logged rather than aborting the run. interlinear_scraper.py's
scrape_interlinear() calls sys.exit(1) on an unrecoverable fetch failure
(by design -- scraper_client.zig's on-demand single-chapter path depends
on that exit code), so this loop must catch SystemExit explicitly, not
just Exception.
"""

import sys
import time

try:
    from tools.bible.interlinear_scraper import scrape_interlinear
except ImportError:
    from interlinear_scraper import scrape_interlinear

OT_BOOKS = {
    "Genesis": 50, "Exodus": 40, "Leviticus": 27, "Numbers": 36, "Deuteronomy": 34,
    "Joshua": 24, "Judges": 21, "Ruth": 4, "1Samuel": 31, "2Samuel": 24, "1Kings": 22,
    "2Kings": 25, "1Chronicles": 29, "2Chronicles": 36, "Ezra": 10, "Nehemiah": 13,
    "Tobit": 14, "Judith": 16, "Esther": 10, "1Meqabyan": 36, "2Meqabyan": 21, "3Meqabyan": 15,
    "Job": 42, "Psalms": 150, "Proverbs": 31, "Tegsas": 31, "Wisdom": 19, "Ecclesiastes": 12,
    "SongofSolomon": 8, "Sirach": 51, "Isaiah": 66, "Jeremiah": 52, "Lamentations": 5,
    "Ezekiel": 48, "Daniel": 12, "Hosea": 14, "Amos": 9, "Micah": 7, "Joel": 3,
    "Obadiah": 1, "Jonah": 4, "Nahum": 3, "Habakkuk": 3, "Zephaniah": 3, "Haggai": 2,
    "Zechariah": 14, "Malachi": 4, "Enoch": 108, "Jubilees": 50,
}

URL_TEMPLATE = "https://biblehub.com/interlinear/apostolic/{book}/{chapter}.htm"


def cache_lxx(books=None):
    books = books or OT_BOOKS
    print("Starting Septuagint (LXX / Apostolic Bible Polyglot) Old Testament Interlinear Cache...")
    sys.stdout.flush()
    ok, skipped = 0, 0
    for book, chapters in books.items():
        print(f"\n>>> {book} <<<")
        sys.stdout.flush()
        for chapter in range(1, chapters + 1):
            try:
                scrape_interlinear(
                    book, chapter,
                    url_template=URL_TEMPLATE,
                    source="LXX",
                    lang_prefix="G",
                )
                ok += 1
                time.sleep(3.0)
            except SystemExit as e:
                print(f"No LXX page for {book} {chapter} (exit {e.code}) -- skipping.")
                sys.stdout.flush()
                skipped += 1
                time.sleep(1.0)
            except Exception as e:
                print(f"Error on {book} {chapter}: {e}")
                sys.stdout.flush()
                skipped += 1
                time.sleep(5.0)
    print(f"\nDone. {ok} chapters cached, {skipped} skipped/missing.")


if __name__ == "__main__":
    cache_lxx()
