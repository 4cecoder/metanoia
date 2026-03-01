import time
import sys
import sqlite3
try:
    from tools.scraper import scrape_chapter
    from tools.interlinear_scraper import scrape_interlinear
    from tools.lexicon_scraper import cache_lexicon_from_db
except ImportError:
    from scraper import scrape_chapter
    from interlinear_scraper import scrape_interlinear
    from lexicon_scraper import cache_lexicon_from_db

# Complete Ethiopian Orthodox Tewahedo Canon (81-88 books)
ETHIOPIAN_CANON = {
    # OT
    "Genesis": 50, "Exodus": 40, "Leviticus": 27, "Numbers": 36, "Deuteronomy": 34,
    "Joshua": 24, "Judges": 21, "Ruth": 4, "1Samuel": 31, "2Samuel": 24, "1Kings": 22,
    "2Kings": 25, "1Chronicles": 29, "2Chronicles": 36, "Ezra": 10, "Nehemiah": 13,
    "Tobit": 14, "Judith": 16, "Esther": 10, "1Meqabyan": 36, "2Meqabyan": 21, "3Meqabyan": 15,
    "Job": 42, "Psalms": 150, "Proverbs": 31, "Tegsas": 31, "Wisdom": 19, "Ecclesiastes": 12,
    "SongofSolomon": 8, "Sirach": 51, "Isaiah": 66, "Jeremiah": 52, "Lamentations": 5,
    "Ezekiel": 48, "Daniel": 12, "Hosea": 14, "Amos": 9, "Micah": 7, "Joel": 3,
    "Obadiah": 1, "Jonah": 4, "Nahum": 3, "Habakkuk": 3, "Zephaniah": 3, "Haggai": 2,
    "Zechariah": 14, "Malachi": 4, "Enoch": 108, "Jubilees": 50,
    # NT
    "Matthew": 28, "Mark": 16, "Luke": 24, "John": 21, "Acts": 28, "Romans": 16,
    "1Corinthians": 16, "2Corinthians": 13, "Galatians": 6, "Ephesians": 6,
    "Philippians": 4, "Colossians": 4, "1Thessalonians": 5, "2Thessalonians": 3,
    "1Timothy": 6, "2Timothy": 4, "Titus": 3, "Philemon": 1, "Hebrews": 13,
    "1Peter": 5, "2Peter": 3, "1John": 5, "2John": 1, "3John": 1, "James": 5,
    "Jude": 1, "Revelation": 22,
    # Church Order
    "SirateTsion": 1, "Tizaz": 1, "Gitsiw": 1, "Abtilis": 1, "1Dominos": 1,
    "2Dominos": 1, "Qalementos": 1, "Didasqalia": 1
}

def cache_everything(version="NKJV"):
    print(f"Starting complete Metanoia Cache for {version}...")
    for book, chapters in ETHIOPIAN_CANON.items():
        print(f"\n--- {book} ({chapters} chapters) ---")
        for chapter in range(1, chapters + 1):
            # 1. Scrape Text
            try:
                scrape_chapter(book, chapter, version)
            except Exception as e:
                print(f"Text error {book} {chapter}: {e}")

            # 2. Scrape Interlinear
            try:
                scrape_interlinear(book, chapter)
            except Exception as e:
                # Many expanded books won't have interlinear on BibleHub
                pass
            
            # 3. Cache new Lexicon entries found in this chapter
            try:
                cache_lexicon_from_db()
            except:
                pass

            # Safety delay to avoid IP block
            time.sleep(3.0)

if __name__ == "__main__":
    ver = sys.argv[1] if len(sys.argv) > 1 else "NKJV"
    cache_everything(ver)
