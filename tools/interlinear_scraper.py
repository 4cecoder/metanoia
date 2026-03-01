import sqlite3
import requests
from bs4 import BeautifulSoup, UnicodeDammit
import sys
import re
import unicodedata

def scrape_interlinear(book, chapter):
    # Determine language prefix based on book (basic NT/OT logic)
    ot_books = ["Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy", "Joshua", "Judges", "Ruth", "1Samuel", "2Samuel", "1Kings", "2Kings", "1Chronicles", "2Chronicles", "Ezra", "Nehemiah", "Esther", "Job", "Psalms", "Proverbs", "Ecclesiastes", "Song of Solomon", "Isaiah", "Jeremiah", "Lamentations", "Ezekiel", "Daniel", "Hosea", "Joel", "Amos", "Obadiah", "Jonah", "Micah", "Nahum", "Habakkuk", "Zephaniah", "Haggai", "Zechariah", "Malachi"]
    prefix = "H" if book in ot_books else "G"

    book_url = book.lower().replace(" ", "")
    url = f"https://biblehub.com/interlinear/{book_url}/{chapter}.htm"
    print(f"Scraping: {url} (Prefix: {prefix})")
    
    headers = {'User-Agent': 'Mozilla/5.0'}
    response = requests.get(url, headers=headers)
    
    dammit = UnicodeDammit(response.content, ["utf-8", "windows-1253", "iso-8859-7"])
    soup = BeautifulSoup(dammit.unicode_markup, 'html.parser')

    conn = sqlite3.connect("data/bible.db")
    cursor = conn.cursor()

    current_verse = 0
    verse_word_index = 0

    for table in soup.find_all("table", class_=["tablefloat", "tablefloatheb"]):
        # Verse Detection
        v_span = table.find("span", class_=["reftop3", "reftop"])
        if v_span:
            v_txt = "".join(filter(str.isdigit, v_span.get_text()))
            if v_txt:
                new_v = int(v_txt)
                if new_v != current_verse:
                    current_verse = new_v
                    verse_word_index = 0 # Reset index for new verse

        if current_verse == 0: continue

        orig = table.find("span", class_=["greek", "heb", "hebrew"])
        if orig:
            text = unicodedata.normalize('NFC', orig.get_text().strip())
            
            s_span = table.find("span", class_=["pos", "strongs"])
            strongs = ""
            if s_span:
                s_link = s_span.find("a")
                raw_s = s_link.get_text().strip() if s_link else s_span.get_text().strip()
                # Ensure prefix is added if missing
                if not raw_s.startswith(("G", "H")):
                    strongs = f"{prefix}{''.join(filter(str.isdigit, raw_s))}"
                else:
                    strongs = raw_s
            
            eng = table.find("span", class_="eng")
            trans = eng.get_text().strip() if eng else ""

            m_spans = table.find_all("span", class_=["strongsnt2", "strongsnt"])
            morph = ""
            for ms in m_spans:
                if ms.find("a", href=re.compile(r"/grammar/")):
                    morph = ms.get_text().strip()
                    break

            # Use verse_word_index instead of global words_processed
            cursor.execute(
                "INSERT OR REPLACE INTO interlinear (book, chapter, verse, word_index, original_text, translation, strongs, morphology) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                (book, chapter, current_verse, verse_word_index, text, trans, strongs, morph)
            )
            verse_word_index += 1

    conn.commit()
    conn.close()
    print(f"Done. Processed interlinear for {book} {chapter}.")

if __name__ == "__main__":
    scrape_interlinear(sys.argv[1], sys.argv[2])
