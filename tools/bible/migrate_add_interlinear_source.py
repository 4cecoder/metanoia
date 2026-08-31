"""One-off migration: add a `source` discriminator column to the
`interlinear` table so the Hebrew Masoretic Text (MT), Greek Septuagint
(LXX, Apostolic Bible Polyglot), and Greek New Testament (GNT) can coexist
for the same (book, chapter, verse, word_index) without clobbering each
other via INSERT OR REPLACE.

Existing rows are NOT deleted -- every row already in the table today is
either Old Testament Hebrew (scraped from biblehub.com/interlinear/, the
Masoretic-based BibleHub interlinear) or New Testament Greek (same URL
template, NT books). This migration tags each existing row 'MT' or 'GNT'
by the testament of its book (via tools/bible_books.json, the same source
of truth interlinear_scraper.py's language_prefix() uses), then rebuilds
the unique index to include `source` so a future LXX scrape can add rows
for the same OT verses without touching the Masoretic rows.

Safe to run more than once (idempotent): skips the ALTER TABLE if the
column already exists, and the UPDATE only ever touches rows still tagged
with the default empty string.
"""

import json
import os
import sqlite3

_DB_PATH = os.path.join(os.path.dirname(__file__), "..", "..", "data", "bible.db")
_BIBLE_BOOKS_PATH = os.path.join(os.path.dirname(__file__), "..", "bible_books.json")


def load_testament_map():
    with open(_BIBLE_BOOKS_PATH, "r", encoding="utf-8") as f:
        return {entry["name"]: entry["testament"] for entry in json.load(f)}


def migrate():
    conn = sqlite3.connect(_DB_PATH)
    cursor = conn.cursor()

    cols = {row[1] for row in cursor.execute("PRAGMA table_info(interlinear)")}
    if "source" not in cols:
        print("Adding interlinear.source column...")
        cursor.execute("ALTER TABLE interlinear ADD COLUMN source TEXT NOT NULL DEFAULT ''")
        conn.commit()
    else:
        print("interlinear.source column already exists.")

    unmigrated = cursor.execute("SELECT COUNT(*) FROM interlinear WHERE source = ''").fetchone()[0]
    print(f"{unmigrated} rows with no source tag yet.")

    if unmigrated:
        testament_map = load_testament_map()
        old_books = [b for b, t in testament_map.items() if t == "Old"]
        new_books = [b for b, t in testament_map.items() if t != "Old"]

        cursor.executemany(
            "UPDATE interlinear SET source='MT' WHERE book=? AND source=''",
            [(b,) for b in old_books],
        )
        cursor.executemany(
            "UPDATE interlinear SET source='GNT' WHERE book=? AND source=''",
            [(b,) for b in new_books],
        )
        conn.commit()

        remaining = cursor.execute("SELECT COUNT(*) FROM interlinear WHERE source = ''").fetchone()[0]
        print(f"Backfilled. {remaining} rows still untagged (unknown book, needs manual check).")

    print("Rebuilding unique index to include source...")
    cursor.execute("DROP INDEX IF EXISTS idx_interlinear_unique")
    cursor.execute(
        "CREATE UNIQUE INDEX idx_interlinear_unique ON interlinear (book, chapter, verse, word_index, source)"
    )
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_interlinear_source ON interlinear (book, chapter, verse, source)")
    conn.commit()

    print("Verification -- rows by source:")
    for source, count in cursor.execute("SELECT source, COUNT(*) FROM interlinear GROUP BY source"):
        print(f"  {source!r}: {count}")

    conn.close()
    print("Done.")


if __name__ == "__main__":
    migrate()
