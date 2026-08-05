import sqlite3
import time
import sys
from scraper import scrape_chapter

BIBLE_BOOKS = {
    "Genesis": 50, "Exodus": 40, "Leviticus": 27, "Numbers": 36, "Deuteronomy": 34,
    "Joshua": 24, "Judges": 21, "Ruth": 4, "1Samuel": 31, "2Samuel": 24, "1Kings": 22,
    "2Kings": 25, "1Chronicles": 29, "2Chronicles": 36, "Ezra": 10, "Nehemiah": 13,
    "Esther": 10, "Job": 42, "Psalms": 150, "Proverbs": 31, "Ecclesiastes": 12,
    "SongofSolomon": 8, "Isaiah": 66, "Jeremiah": 52, "Lamentations": 5, "Ezekiel": 48,
    "Daniel": 12, "Hosea": 14, "Joel": 3, "Amos": 9, "Obadiah": 1, "Jonah": 4,
    "Micah": 7, "Nahum": 3, "Habakkuk": 3, "Zephaniah": 3, "Haggai": 2, "Zechariah": 14,
    "Malachi": 4, "Matthew": 28, "Mark": 16, "Luke": 24, "John": 21, "Acts": 28,
    "Romans": 16, "1Corinthians": 16, "2Corinthians": 13, "Galatians": 6, "Ephesians": 6,
    "Philippians": 4, "Colossians": 4, "1Thessalonians": 5, "2Thessalonians": 3,
    "1Timothy": 6, "2Timothy": 4, "Titus": 3, "Philemon": 1, "Hebrews": 13, "James": 5,
    "1Peter": 5, "2Peter": 3, "1John": 5, "2John": 1, "3John": 1, "Jude": 1, "Revelation": 22
}

def recover_missing(version="NKJV"):
    conn = sqlite3.connect("data/bible.db")
    cursor = conn.cursor()
    
    for book, chapters in BIBLE_BOOKS.items():
        print(f"Checking {book}...")
        cursor.execute("SELECT DISTINCT chapter FROM verses WHERE book=? AND version=?", (book, version))
        existing_chapters = {row[0] for row in cursor.fetchall()}
        
        missing = [c for c in range(1, chapters + 1) if c not in existing_chapters]
        
        if missing:
            print(f"Found {len(missing)} missing chapters for {book}: {missing}")
            for chapter in missing:
                retries = 3
                while retries > 0:
                    try:
                        scrape_chapter(book, chapter, version)
                        time.sleep(2.0)
                        break
                    except Exception as e:
                        print(f"Error scraping {book} {chapter}: {e}. Retrying...")
                        retries -= 1
                        time.sleep(5.0)
        else:
            print(f"All {chapters} chapters of {book} are already cached.")
            
    conn.close()

if __name__ == "__main__":
    ver = sys.argv[1] if len(sys.argv) > 1 else "NKJV"
    recover_missing(ver)
