import time
import sys
try:
    from tools.interlinear_scraper import scrape_interlinear
except ImportError:
    from interlinear_scraper import scrape_interlinear

NT_BOOKS = {
    "Matthew": 28, "Mark": 16, "Luke": 24, "John": 21, "Acts": 28, "Romans": 16,
    "1Corinthians": 16, "2Corinthians": 13, "Galatians": 6, "Ephesians": 6,
    "Philippians": 4, "Colossians": 4, "1Thessalonians": 5, "2Thessalonians": 3,
    "1Timothy": 6, "2Timothy": 4, "Titus": 3, "Philemon": 1, "Hebrews": 13,
    "James": 5, "1Peter": 5, "2Peter": 3, "1John": 5, "2John": 1, "3John": 1,
    "Jude": 1, "Revelation": 22
}

def cache_nt():
    print("Starting full New Testament Interlinear Cache...")
    for book, chapters in NT_BOOKS.items():
        print(f"
>>> {book} <<<")
        for chapter in range(1, chapters + 1):
            try:
                scrape_interlinear(book, chapter)
                # Respectful delay
                time.sleep(3.0)
            except Exception as e:
                print(f"Error on {book} {chapter}: {e}")
                time.sleep(5.0)

if __name__ == "__main__":
    cache_nt()
