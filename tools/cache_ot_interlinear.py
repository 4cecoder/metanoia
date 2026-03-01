import time
import sys
try:
    from tools.interlinear_scraper import scrape_interlinear
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
    "Zechariah": 14, "Malachi": 4, "Enoch": 108, "Jubilees": 50
}

def cache_ot():
    print("Starting full Old Testament (Hebrew) Interlinear Cache...")
    for book, chapters in OT_BOOKS.items():
        print(f"\n>>> {book} <<<")
        for chapter in range(1, chapters + 1):
            try:
                # Our scraper handles Hebrew automatically by detecting the .heb class
                scrape_interlinear(book, chapter)
                time.sleep(3.0)
            except Exception as e:
                print(f"Error on {book} {chapter}: {e}")
                time.sleep(5.0)

if __name__ == "__main__":
    cache_ot()
