import sqlite3
import os

def populate():
    db_path = "data/bible.db"
    if not os.path.exists(db_path):
        print("DB not found")
        return

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Ensure table exists (though Zig does this on startup too)
    cursor.execute("CREATE TABLE IF NOT EXISTS book_metadata (book TEXT PRIMARY KEY, author TEXT, date TEXT, audience TEXT, context TEXT)")

    metadata = [
        ("John", "Apostle John", "c. 85-95 AD", "General / Believers", "Written to prove Jesus is the Son of God through signs and the 'I Am' statements. Provides high-christology and unique theological discourse not found in synoptics."),
        ("Romans", "Apostle Paul", "c. 57 AD", "Believers in Rome", "The most systematic presentation of the gospel, focusing on justification by faith, the role of Israel, and Christian living in a pagan capital."),
        ("Genesis", "Moses", "c. 1440-1400 BC", "Israelites in the wilderness", "Foundational book of origins: creation, fall, and the covenantal history of the patriarchs. Establishes the identity of Israel as God's chosen people."),
        ("James", "James (brother of Jesus)", "c. 45-50 AD", "Jewish Christians in the Diaspora", "One of the earliest NT books. Focuses on practical wisdom, the relationship between faith and works, and trials in the life of a believer."),
        ("Isaiah", "Isaiah son of Amoz", "c. 740-680 BC", "Judah and Jerusalem", "Major prophetic book dealing with judgment, the holiness of God, and extensive Messianic prophecies including the 'Suffering Servant'."),
    ]

    for m in metadata:
        cursor.execute("INSERT OR REPLACE INTO book_metadata VALUES (?, ?, ?, ?, ?)", m)
    
    # Add Chapter Summaries
    cursor.execute("CREATE TABLE IF NOT EXISTS chapter_summaries (book TEXT, chapter INTEGER, summary TEXT, PRIMARY KEY(book, chapter))")
    summaries = [
        ("John", 3, "Jesus' discourse with Nicodemus about being born again, the love of God manifested in the Son, and the transition from the ministry of John the Baptist to Christ."),
        ("Romans", 1, "Paul's introduction to the Roman believers, the power of the Gospel for salvation, and the revelation of God's wrath against human unrighteousness."),
        ("James", 1, "Exhortations on enduring trials with joy, seeking wisdom from God, being doers of the word and not hearers only, and the nature of pure religion."),
    ]
    for s in summaries:
        cursor.execute("INSERT OR REPLACE INTO chapter_summaries VALUES (?, ?, ?)", s)
    
    conn.commit()
    conn.close()
    print("Metadata and summaries populated for core books.")

if __name__ == "__main__":
    populate()
