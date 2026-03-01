import sqlite3
import time
import sys
try:
    from tools.scraper import scrape_chapter
    from tools.interlinear_scraper import scrape_interlinear
    from tools.lexicon_scraper import cache_lexicon_from_db
except ImportError:
    from scraper import scrape_chapter
    from interlinear_scraper import scrape_interlinear
    from lexicon_scraper import cache_lexicon_from_db

def fill_all():
    conn = sqlite3.connect("data/bible.db")
    cursor = conn.cursor()
    
    # Get all chapters we have verses for
    cursor.execute("SELECT DISTINCT book, chapter FROM verses")
    chapters = cursor.fetchall()
    
    print(f"Checking interlinear for {len(chapters)} chapters...")
    sys.stdout.flush() # Force flush for nohup log visibility
    
    for book, chapter in chapters:
        # Check if we already have interlinear data for this chapter
        cursor.execute("SELECT 1 FROM interlinear WHERE book=? AND chapter=? LIMIT 1", (book, chapter))
        if cursor.fetchone():
            continue
            
        print(f"Fetching interlinear for {book} {chapter}...")
        sys.stdout.flush()
        try:
            scrape_interlinear(book, chapter)
            # After each chapter, also ensure lexicon is updated for any new Strong's numbers
            cache_lexicon_from_db()
            time.sleep(3.0) # Respectful delay
        except Exception as e:
            print(f"Error on {book} {chapter}: {e}")
            sys.stdout.flush()
            time.sleep(10.0) # Longer wait on error
            
    conn.close()

if __name__ == "__main__":
    fill_all()
