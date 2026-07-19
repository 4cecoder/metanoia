import sqlite3
import requests
from bs4 import BeautifulSoup
import sys
import time

try:
    from tools.scraper_common import fetch_with_retry
except ImportError:
    from scraper_common import fetch_with_retry

def scrape_strongs(strongs_num, language="greek"):
    # BibleHub format: https://biblehub.com/greek/1.htm or /hebrew/1.htm
    url = f"https://biblehub.com/{language}/{strongs_num}.htm"
    print(f"Fetching Dictionary Entry: {url}...")

    headers = {'User-Agent': 'Mozilla/5.0'}
    try:
        response = fetch_with_retry(url, headers=headers, timeout=15)
        if response.status_code != 200: return None
    except requests.RequestException as e:
        print(f"Failed to fetch {url}: {e}")
        return None

    soup = BeautifulSoup(response.text, "html.parser")
    
    # Extract details
    lemma = ""
    translit = ""
    definition = ""
    usage = ""

    # Lemma and Translit are usually in the top section
    # BibleHub often has 'Strong's Concordance' section
    strongs_heading = soup.find("div", class_="strongs")
    if strongs_heading:
        # This parsing depends on the specific BibleHub layout for Strong's
        # Let's try to get the summary text
        main_content = soup.find("div", id="leftbox")
        if main_content:
            text = main_content.get_text()
            # Basic extraction - in a real app we'd use more precise selectors
            definition = " ".join(text.split()[:100]) # First 100 words as fallback

    # Better extraction for Definition and Usage
    # Look for "Definition" and "Thayer's Greek Lexicon" etc.
    def_section = soup.find("div", class_="strongsnt")
    if def_section:
        definition = def_section.get_text().strip()

    return {
        "strongs": f"{'G' if language == 'greek' else 'H'}{strongs_num}",
        "language": language,
        "lemma": lemma,
        "translit": translit,
        "definition": definition,
        "usage": usage
    }

def cache_lexicon_from_db(book=None, chapter=None):
    """Backfill the lexicon table with Strong's-number entries referenced by
    the interlinear table but not yet cached.

    With no arguments, scans the whole interlinear table (maintenance/standalone
    run, e.g. `python tools/lexicon_scraper.py`). Pass `book`/`chapter` to
    scope the scan to just that chapter's Strong's numbers -- e.g. after a
    single-chapter interlinear scrape, so a single verse lookup doesn't pay
    for a full-database backfill pass.
    """
    conn = sqlite3.connect("data/bible.db")
    cursor = conn.cursor()

    if book is not None and chapter is not None:
        # Scoped: only Strong's numbers introduced by this one chapter.
        cursor.execute(
            "SELECT DISTINCT strongs FROM interlinear WHERE strongs != '' AND book = ? AND chapter = ?",
            (book, chapter),
        )
    else:
        # Whole-database backfill.
        cursor.execute("SELECT DISTINCT strongs FROM interlinear WHERE strongs != ''")
    strongs_list = [row[0] for row in cursor.fetchall()]
    
    # Prioritize Greek (G) then Hebrew (H)
    strongs_list.sort(key=lambda x: (0 if x.startswith('G') else 1, x))
    
    for s in strongs_list:
        # Check if already in lexicon
        cursor.execute("SELECT 1 FROM lexicon WHERE strongs = ?", (s,))
        if cursor.fetchone(): continue
        
        # Parse language and number
        lang = "greek" if s.startswith("G") else "hebrew"
        num = "".join(filter(str.isdigit, s))
        
        data = scrape_strongs(num, lang)
        if data:
            cursor.execute(
                "INSERT OR REPLACE INTO lexicon (strongs, language, lemma, transliteration, definition, usage) VALUES (?, ?, ?, ?, ?, ?)",
                (data["strongs"], data["language"], data["lemma"], data["translit"], data["definition"], data["usage"])
            )
            print(f"Cached Lexicon: {s}")
            conn.commit()
            time.sleep(1.0) # Respectful delay

    conn.close()


def _parse_args(argv):
    """Returns (book, chapter) from CLI args, or (None, None) for the
    whole-database mode. Split out from __main__ so it's unit-testable
    without executing the module as a script."""
    if len(argv) >= 3:
        return argv[1], int(argv[2])
    return None, None


if __name__ == "__main__":
    # Optional `book chapter` args scope the backfill to one chapter; with no
    # args, falls back to the whole-database maintenance scan.
    _book, _chapter = _parse_args(sys.argv)
    if _book is not None:
        cache_lexicon_from_db(_book, _chapter)
    else:
        cache_lexicon_from_db()
