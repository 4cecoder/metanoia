import sqlite3
import requests
from bs4 import BeautifulSoup
import sys
import re

def scrape_chapter(book, chapter, version="NKJV"):
    url = f"https://www.biblegateway.com/passage/?search={book}+{chapter}&version={version}&interface=print"
    print(f"Fetching {url}...")
    
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
    }
    response = requests.get(url, headers=headers)
    if response.status_code != 200:
        print(f"Failed to fetch {url}")
        return

    soup = BeautifulSoup(response.text, "html.parser")
    
    # Remove all headings immediately to avoid versification of titles
    for heading in soup.find_all(["h1", "h2", "h3", "h4", "h5", "h6"]):
        heading.decompose()

    conn = sqlite3.connect("data/bible.db")
    cursor = conn.cursor()

    # Dictionary to store concatenated verse text
    # Key: verse_num, Value: list of text segments
    verse_map = {}
    
    passage_texts = soup.find_all("div", class_="passage-text")
    for passage in passage_texts:
        spans = passage.find_all("span", class_="text")
        for span in spans:
            classes = span.get("class", [])
            verse_num = None
            for c in classes:
                # Look for the verse number in the class name
                m = re.search(r"-(\d+)$", c)
                if m:
                    verse_num = int(m.group(1))
                    break
            
            if verse_num:
                # Clean up footnotes, cross-refs, and internal verse/chapter numbers
                for extra in span.find_all(["sup", "span"], class_=["footnote", "crossreference", "chapternum", "versenum"]):
                    extra.decompose()
                
                text = span.get_text().strip()
                if not text:
                    continue

                if verse_num not in verse_map:
                    verse_map[verse_num] = []
                verse_map[verse_num].append(text)

    # Insert concatenated verses into DB
    count = 0
    for vn, segments in verse_map.items():
        full_text = " ".join(segments)
        # Clean up double spaces that might arise from joining
        full_text = re.sub(r'\s+', ' ', full_text).strip()
        
        cursor.execute(
            "INSERT OR REPLACE INTO verses (book, chapter, verse, text, version) VALUES (?, ?, ?, ?, ?)",
            (book, chapter, vn, full_text, version)
        )
        count += 1

    conn.commit()
    conn.close()
    print(f"Successfully processed {count} unique verses for {book} {chapter} ({version})")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python3 scraper.py <book> <chapter> [version]")
    else:
        book = sys.argv[1]
        chapter = sys.argv[2]
        version = sys.argv[3] if len(sys.argv) > 3 else "NKJV"
        scrape_chapter(book, chapter, version)
