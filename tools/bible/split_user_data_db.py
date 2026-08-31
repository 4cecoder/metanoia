"""One-off migration: split personal/volatile user data (bookmarks, notes,
highlights, lexical_favorites, vocab_list) out of data/bible.db into its
own data/library.db.

Why: data/bible.db is *content* -- verses, interlinear, lexicon -- and gets
wholesale-replaced every time the app is rebuilt/reinstalled (see
packaging/build-macos.sh, which copies the repo's data/bible.db straight
into the .app bundle; a fresh install or update overwrites it entirely).
Personal data mixed into that same file would be silently destroyed on
every update. Splitting by volatility means the content DB can be
replaced/updated freely while a separate, stable-location library DB
(outside the app bundle -- see bible_db.zig's userDataDbPath()) survives
app updates untouched.

Safe to run more than once (idempotent): skips a table's copy if
data/library.db already has that table with the same-or-more rows.
"""

import os
import sqlite3

_CONTENT_DB = os.path.join(os.path.dirname(__file__), "..", "..", "data", "bible.db")
_LIBRARY_DB = os.path.join(os.path.dirname(__file__), "..", "..", "data", "library.db")

USER_DATA_TABLES = {
    "bookmarks": "CREATE TABLE IF NOT EXISTS bookmarks (id INTEGER PRIMARY KEY, book TEXT, chapter INTEGER, verse INTEGER, note TEXT, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)",
    "notes": "CREATE TABLE IF NOT EXISTS notes (id INTEGER PRIMARY KEY AUTOINCREMENT, book TEXT, chapter INTEGER, verse INTEGER, content TEXT, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)",
    "highlights": "CREATE TABLE IF NOT EXISTS highlights (book TEXT, chapter INTEGER, verse INTEGER, color TEXT, PRIMARY KEY(book, chapter, verse))",
    "lexical_favorites": "CREATE TABLE IF NOT EXISTS lexical_favorites (strongs TEXT PRIMARY KEY, lemma TEXT, definition TEXT)",
    "vocab_list": "CREATE TABLE IF NOT EXISTS vocab_list (id INTEGER PRIMARY KEY, word TEXT, language TEXT, strongs TEXT, definition TEXT)",
}


def split():
    # A background LXX interlinear scrape may still be writing to
    # data/bible.db (short-lived connections, one per chapter) while this
    # runs -- a generous busy timeout rides through any lock collision
    # instead of failing immediately.
    content = sqlite3.connect(_CONTENT_DB, timeout=30)
    library = sqlite3.connect(_LIBRARY_DB, timeout=30)

    content_tables = {
        row[0] for row in content.execute("SELECT name FROM sqlite_master WHERE type='table'")
    }

    for table, create_sql in USER_DATA_TABLES.items():
        library.execute(create_sql)
        library.commit()

        if table not in content_tables:
            print(f"{table}: not in data/bible.db, nothing to copy.")
            continue

        rows = content.execute(f"SELECT * FROM {table}").fetchall()
        cols = [d[0] for d in content.execute(f"SELECT * FROM {table} LIMIT 0").description]
        if rows:
            placeholders = ",".join("?" * len(cols))
            library.executemany(
                f"INSERT OR IGNORE INTO {table} ({','.join(cols)}) VALUES ({placeholders})", rows
            )
            library.commit()
        print(f"{table}: copied {len(rows)} row(s) to data/library.db")

        content.execute(f"DROP TABLE IF EXISTS {table}")
        content.commit()

    content.execute("VACUUM")
    content.commit()
    content.close()
    library.close()
    print("\nDone. data/bible.db is now content-only; personal data lives in data/library.db.")


if __name__ == "__main__":
    split()
