import time
try:
    from tools.interlinear_scraper import scrape_interlinear
except ImportError:
    from interlinear_scraper import scrape_interlinear

def cache_james():
    book = "James"
    chapters = 5
    print(f"Caching Interlinear for {book}...")
    for chapter in range(1, chapters + 1):
        try:
            print(f"Scraping {book} {chapter}...")
            scrape_interlinear(book, chapter)
            # Respectful delay to prevent being blocked
            time.sleep(2.0)
        except Exception as e:
            print(f"Error on {book} {chapter}: {e}")
            time.sleep(5.0)
    print("James interlinear caching complete.")

if __name__ == "__main__":
    cache_james()
