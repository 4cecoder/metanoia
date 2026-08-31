r"""Import World English Bible (WEB, public domain) into a sharded
`verses.web.db` as version='WEB' — the PD replacement for the NKJV trap.

Why WEB
-------
Metanoia ships `verses version='NKJV'` 31,102 as `src/bible_db.zig:476
DEFAULT_VERSION` (Thomas Nelson, 1982 — not PD).  FedoraBible's
`data/sources/SOURCE.md:1` explicitly excludes NIV/ESV/NKJV/NASB:
"hosting their full text isn't something this project does."  The fix
from `docs/DB_SHARDING.md` is sharding:

  verses.web.db  (WEB, PD via ebible.org) replaces the NKJV shard
  verses.lxxe.db (Brenton 1851, PD) stays the primary OT English
  verses.lxxm.db (deterministic moderniser of Brenton) optional

This importer populates the WEB shard so `manifest.json` can flip:

  { file: "verses.nkjv.db", primacy: "buried", bundle: false,
    replaced_by: "verses.web.db" }
  { file: "verses.web.db",  primacy: "comparison", license: "PD (WEB, ebible.org)",
    filter: "verses.version='WEB'" }

Source & shape — Fedora parallel
---------------------------------
Fedora keeps every translation as "per-version files before merge"
(`data/sources/kjv/*.json` + `lxx-en/*.usfm` + `lxx-gr/*.txt` — see
`docs/FEDORA_AUDIT.md §4` and `docs/DB_SHARDING.md:Site`).

Two importer shapes are relevant:

  * Fedora `scripts/import-translation.js` — one JSON per book
    `{ book, chapters:[{ chapter, verses:[{ verse, text }]}] }`
    + optional `Books.json`, then `lib/import-core.js:runImport()`
    does `DELETE FROM verses WHERE translation_code=?` + batched INSERT.
    Used for KJV, PESH, COPS.  Our Python analogue for a vendored
    per-book JSON directory is `--dir data/sources/web` (see `load_json_book()`).

  * Fedora `scripts/import-usfm.js` + `lib/usfm.js` — one `<CODE>.usfm`
    per book (GEN, PSA …) parsed with footnote-stripping and `35a→35`
    folding, then the same `runImport()` core.  That's what WEB actually
    ships as from eBible.org: a single USFM zip
    `https://eBible.org/Scriptures/eng-web_usfm.zip` (3.2 MB, 86 files
    like `02-GENeng-web.usfm`) — preferred over the HTML zip because the
    USFM preserves `\f`/`\x` footnotes and `\w strong="H..."` annotations
    cleanly and matches Brenton's own `eng-Brenton_usfm.zip` shape.
    Our USFM path mirrors both `lib/usfm.js:parseUsfm()` *and*
    `tools/bible/import_brenton_septuagint.py:130-150` which does
    `parse_chapter(html)` → `cursor.executemany(INSERT OR REPLACE ...)`.

The HTML alternative `https://eBible.org/Scriptures/eng-web_html.zip`
(5.1 MB, `GEN01.htm` with `<span class="verse" id="V1">1 `) is the same
template `import_brenton_septuagint.py` already handles via
`BeautifulSoup … span.verse sentinel \\x00`.  We support it as a fallback,
but USFM is canonical.

Target shard & predicate
-------------------------
  file:   data/db/verses.web.db  (default; override with --out)
  table:  verses (id PK, book TEXT, chapter INT, verse INT, text TEXT,
                  version TEXT, footnotes TEXT)
          + UNIQUE idx_verse_lookup (book, chapter, verse, version)
          versions (slug, name)
  filter: verses.version='WEB'   — same predicate `tools/bible/split_db.py:46`
          would use to carve the monolith.
  license: PD (WEB, ebible.org) — the 2020 stable text is explicitly
           public domain; "World English Bible" is trademark only.
Usage
-----
  # Preferred — fetch once to temp (no vendoring needed):
  uv run python3 tools/bible/import_web.py
  uv run python3 tools/bible/import_web.py --out data/db/verses.web.db

  # Offline / vendored per-book JSON (Fedora shape):
  uv run python3 tools/bible/import_web.py --dir data/sources/web

  # Offline USFM zip already downloaded:
  uv run python3 tools/bible/import_web.py /tmp/eng-web_usfm.zip

Does NOT touch data/bible.db (monolith).  To carve a legacy monolith, run
`tools/bible/split_db.py --source data/bible.db --out data/db` after.

See also: deterministic post-process `tools/bible/modernize_brenton.py`
which creates `verses.lxxm.db` version='LXXM' from `verses.lxxe.db`
without re-scraping (thou→you, hath→has, …).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sqlite3
import sys
import tempfile
import zipfile
from pathlib import Path

import requests  # same dep as import_brenton_septuagint.py

# ---------------------------------------------------------------------------
# Paths / constants — siblings to import_brenton_septuagint.py
# ---------------------------------------------------------------------------
_REPO_ROOT = Path(__file__).resolve().parents[2]
_DEFAULT_OUT = _REPO_ROOT / "data" / "db" / "verses.web.db"
_LEGACY_DB = _REPO_ROOT / "data" / "bible.db"
_ZIP_URL = "https://eBible.org/Scriptures/eng-web_usfm.zip"
_HTML_ZIP_URL = "https://eBible.org/Scriptures/eng-web_html.zip"
_VERSION = "WEB"
_VERSION_NAME = "World English Bible (WEB, 2020 stable, PD)"

# USFM book codes as they appear inside the zip: files are named
# `02-GENeng-web.usfm` etc.; \id line is `GEN`.  Map to Metanoia
# `BIBLE_BOOKS` names (src/bible_db.zig:334-422, tools/bible_books.json).
USFM_CODE_TO_BOOK: dict[str, str] = {
    # OT Protestant 39 (Fedora's lib/usfm-books.js order)
    "GEN": "Genesis", "EXO": "Exodus", "LEV": "Leviticus", "NUM": "Numbers",
    "DEU": "Deuteronomy", "JOS": "Joshua", "JDG": "Judges", "RUT": "Ruth",
    "1SA": "1Samuel", "2SA": "2Samuel", "1KI": "1Kings", "2KI": "2Kings",
    "1CH": "1Chronicles", "2CH": "2Chronicles", "EZR": "Ezra", "NEH": "Nehemiah",
    "EST": "Esther", "JOB": "Job", "PSA": "Psalms", "PRO": "Proverbs",
    "ECC": "Ecclesiastes", "SNG": "SongofSolomon", "ISA": "Isaiah",
    "JER": "Jeremiah", "LAM": "Lamentations", "EZK": "Ezekiel", "DAN": "Daniel",
    "HOS": "Hosea", "JOL": "Joel", "AMO": "Amos", "OBA": "Obadiah",
    "JON": "Jonah", "MIC": "Micah", "NAM": "Nahum", "HAB": "Habakkuk",
    "ZEP": "Zephaniah", "HAG": "Haggai", "ZEC": "Zechariah", "MAL": "Malachi",
    # Deuterocanon / Apocrypha present in WEB's USFM (and in BIBLE_BOOKS)
    "TOB": "Tobit", "JDT": "Judith",
    # WEB uses ESG for Greek Esther, DAG for Greek Daniel — both map onto
    # the single Protestant book entries; LXX expansions handled separately
    "ESG": "Esther",  # Greek Esther — folded onto Esther (like Brenton ESG→Esther)
    "DAG": "Daniel",  # Greek Daniel (Theodotion) — folded onto Daniel
    "WIS": "Wisdom", "SIR": "Sirach", "BAR": "Baruch",
    "1MA": "1Maccabees", "2MA": "2Maccabees",
    # WEB also ships 1ES(3 Esdras), MAN, PS2(151), 3MA, 2ES, 4MA — not in
    # BIBLE_BOOKS today; kept for forward compatibility (logs as skip unless
    # caller adds them).  Uncomment to import if you extend BIBLE_BOOKS:
    # "1ES": "1Esdras", "MAN": "PrayerOfManasseh", "PS2": "Psalm151",
    # "3MA": "3Maccabees", "2ES": "2Esdras", "4MA": "4Maccabees",
    "GLO": "__skip__",  # Glossary — not a book
    # NT 27
    "MAT": "Matthew", "MRK": "Mark", "LUK": "Luke", "JHN": "John",
    "ACT": "Acts", "ROM": "Romans", "1CO": "1Corinthians", "2CO": "2Corinthians",
    "GAL": "Galatians", "EPH": "Ephesians", "PHP": "Philippians", "COL": "Colossians",
    "1TH": "1Thessalonians", "2TH": "2Thessalonians", "1TI": "1Timothy", "2TI": "2Timothy",
    "TIT": "Titus", "PHM": "Philemon", "HEB": "Hebrews", "JAS": "James",
    "1PE": "1Peter", "2PE": "2Peter", "1JN": "1John", "2JN": "2John", "3JN": "3John",
    "JUD": "Jude", "REV": "Revelation",
}

# Reverse for HTML zip shape (filenames like GEN01.htm, PSA001.htm)
# — mirrors import_brenton_septuagint.py:BOOK_MAP (3-letter code, chapter count).
HTML_BOOK_MAP: dict[str, tuple[str, int]] = {
    # Minimal mapping derived from USFM_CODE_TO_BOOK plus chapter counts from
    # BIBLE_BOOKS; only used when --html-zip is chosen.  Counts omitted here
    # for brevity — HTML importer iterates until missing file like Brenton does.
}


# ---------------------------------------------------------------------------
# USFM parser — Python port of Fedora's lib/usfm.js:parseUsfm()
# ---------------------------------------------------------------------------
_USFM_FOOTNOTE_RE = re.compile(r"\\f\s*\+?[\s\S]*?\\f\*")
_USFM_XREF_RE = re.compile(r"\\x\s*\+?[\s\S]*?\\x\*")
# \w ...\w* and \+w ...\w* (WEB's word-level Strong's) — keep inner text
_USFM_W_RE = re.compile(r"\\\+?w\s*([^|]*)\|[^\\]*?\\\+?w\*")
_USFM_W2_RE = re.compile(r"\\w\s+([^\s|]+)\|[^\\]*?\\w\*")  # fallback
_USFM_C_RE = re.compile(r"^\\c\s+(\d+)")
_USFM_V_RE = re.compile(r"^\\v\s+(\d+)[a-z]?\s?(.*)$")  # fold 35a→35
_USFM_MARKER_RE = re.compile(r"\\[a-z][a-z0-9]*\*?", re.IGNORECASE)


def _strip_usfm_inline(text: str) -> str:
    """Drop footnotes/xrefs entirely, keep character-style text (add, sc, w, etc.)."""
    text = _USFM_FOOTNOTE_RE.sub("", text)
    text = _USFM_XREF_RE.sub("", text)
    # \w ...\w* — WEB annotates every word with Strong's; keep the surface word
    text = _USFM_W_RE.sub(r"\1", text)
    text = _USFM_W2_RE.sub(r"\1", text)
    # Strip remaining markers like \add \add*, \sc …\sc*, \bd, \it, \nd …
    # but preserve \c and \v lines' structural meaning (handled separately).
    # This is the same allowlist trick as lib/usfm.js (drop character-styles,
    # keep c/v).
    def _drop_marker(m: re.Match[str]) -> str:
        tok = m.group(0)
        if re.match(r"^\\(c|v)\b", tok, re.I):
            return tok
        if tok.endswith("*"):
            return ""
        # bare marker with optional trailing space
        return ""

    # First collapse the \f/\x spans above, then drop character markers
    # while keeping \c/\v tokens so the line parser still sees them.
    # For inline markers that used to carry text (\add foo\add*), the text
    # remains because we only remove the marker tokens themselves.
    text = _USFM_MARKER_RE.sub(_drop_marker, text)
    # WEB also uses \+wh …\+wh* inside footnotes for Hebrew; already stripped,
    # but belt-and-suspenders for stray occurrences.
    text = re.sub(r"\\\+wh\s*", "", text)
    text = re.sub(r"\\\+wh\*", "", text)
    return text


def parse_usfm(raw: str) -> list[dict]:
    """Parse one USFM file into Fedora-shaped chapters: [{ chapter, verses:[{verse,text}]}].

    Faithful to lib/usfm.js: handles 35a-letter suffix folding, paragraph
    continuations appended to the open verse, whitespace normalization.
    """
    cleaned = _strip_usfm_inline(raw)
    chapters: list[dict] = []
    cur_ch: dict | None = None
    cur_v: dict | None = None

    for line in cleaned.splitlines():
        line = line.rstrip()
        if not line:
            continue
        c_m = _USFM_C_RE.match(line)
        if c_m:
            cur_ch = {"chapter": int(c_m.group(1)), "verses": []}
            chapters.append(cur_ch)
            cur_v = None
            continue
        v_m = _USFM_V_RE.match(line)
        if v_m:
            if cur_ch is None:
                continue
            num = int(v_m.group(1))
            txt = v_m.group(2).strip()
            # Fold 35a/35b into base 35 — same as Fedora's existing.find(v=>v.verse==num)
            existing = next((v for v in cur_ch["verses"] if v["verse"] == num), None)
            if existing:
                existing["text"] += " " + txt
                cur_v = existing
            else:
                cur_v = {"verse": num, "text": txt}
                cur_ch["verses"].append(cur_v)
            continue
        # Continuation / paragraph marker line — append to open verse
        if cur_v is not None and line and not line.startswith("\\"):
            cur_v["text"] += " " + line.strip()
        elif cur_v is not None:
            stripped = re.sub(r"^\\\S+\s*", "", line).strip()
            if stripped:
                cur_v["text"] += " " + stripped

    for ch in chapters:
        for v in ch["verses"]:
            v["text"] = re.sub(r"\s+", " ", v["text"]).strip()
    return [ch for ch in chapters if ch["verses"]]


# ---------------------------------------------------------------------------
# JSON per-book shape (Fedora's import-translation.js)
# ---------------------------------------------------------------------------
def load_json_book(path: Path) -> dict:
    """Load one per-book JSON file in Fedora's aruljohn/Bible-kjv shape."""
    data = json.loads(path.read_text(encoding="utf-8"))
    # Support both {book, chapters:[{chapter, verses:[{verse,text}]}]}
    # and {englishName, chapters:[{chapter, verses:[{number,text}]}]} (midvash)
    book = data.get("book") or data.get("englishName") or path.stem
    # Normalize chapter/verse keys to str/int agnostic
    chapters = []
    for ch in data.get("chapters", []):
        cnum = ch.get("chapter")
        verses = []
        for v in ch.get("verses", []):
            vnum = v.get("verse", v.get("number", v.get("verse")))
            txt = v.get("text", "")
            if txt and str(txt).strip():
                verses.append({"verse": int(vnum), "text": str(txt).strip()})
        if verses:
            chapters.append({"chapter": int(cnum), "verses": verses})
    return {"name": book, "chapters": chapters}


# ---------------------------------------------------------------------------
# DB helpers — shards, not monolith (mirrors split_db.py predicates)
# ---------------------------------------------------------------------------
DDL_VERSES = """
CREATE TABLE IF NOT EXISTS verses (
  id INTEGER PRIMARY KEY,
  book TEXT, chapter INTEGER, verse INTEGER, text TEXT,
  version TEXT, footnotes TEXT
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_verse_lookup ON verses (book, chapter, verse, version);
CREATE TABLE IF NOT EXISTS versions (slug TEXT PRIMARY KEY, name TEXT);
"""

def ensure_db(path: Path) -> sqlite3.Connection:
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(path))
    conn.executescript(DDL_VERSES)
    return conn


def fetch_zip(url: str, dest: Path | None = None) -> Path:
    """Fetch zip once to temp (idempotent) — mirrors import_brenton's ensure_zip."""
    if dest and dest.exists():
        return dest
    tmp = Path(tempfile.gettempdir()) / Path(url).name
    if tmp.exists() and tmp.stat().st_size > 0:
        return tmp
    print(f"Downloading {url} ...")
    resp = requests.get(url, headers={"User-Agent": "Mozilla/5.0"}, timeout=60)
    resp.raise_for_status()
    tmp.write_bytes(resp.content)
    print(f"  -> {tmp} ({tmp.stat().st_size / (1<<20):.1f} MB)")
    return tmp


# ---------------------------------------------------------------------------
# Main import — mirrors import_brenton_septuagint.py:130-150
# ---------------------------------------------------------------------------
def import_web(
    zip_path: str | Path | None = None,
    json_dir: str | Path | None = None,
    out: str | Path = _DEFAULT_OUT,
    use_html: bool = False,
) -> None:
    out = Path(out)
    total = 0
    conn = ensure_db(out)
    cur = conn.cursor()

    # JSON dir path — Fedora-shaped per-book files (import-translation.js)
    if json_dir:
        src = Path(json_dir)
        if not src.is_dir():
            print(f"JSON dir not found: {src}", file=sys.stderr)
            sys.exit(1)
        # Books.json optional, else scan *.json like import-translation.js
        books_json = src / "Books.json"
        if books_json.exists():
            book_names = json.loads(books_json.read_text(encoding="utf-8"))
            files = [src / (n.replace(" ", "") + ".json") for n in book_names]
        else:
            files = sorted(src.glob("*.json"))
            # skip Books.json itself if present lowercased
            files = [p for p in files if p.name.lower() != "books.json"]
        for fp in files:
            entry = load_json_book(fp)
            bname = entry["name"].replace(" ", "")
            # Normalize "1 Samuel" vs "1Samuel" — BIBLE_BOOKS uses no space
            bname = bname
            # Try to map via loose match (Fedora uses exact books.name;
            # Metanoia's BIBLE_BOOKS is spaceless for numbered books)
            mapped = bname if bname in {b for b in USFM_CODE_TO_BOOK.values() if b != "__skip__"} else bname
            # If file's book name has spaces, collapse them
            if " " in entry["name"]:
                mapped = entry["name"].replace(" ", "")
            # Fall back to raw entry name with space stripped
            book = mapped
            for ch in entry["chapters"]:
                cur.executemany(
                    "INSERT OR REPLACE INTO verses (book, chapter, verse, text, version) VALUES (?, ?, ?, ?, ?)",
                    [(book, ch["chapter"], v["verse"], v["text"], _VERSION) for v in ch["verses"]],
                )
                total += len(ch["verses"])
            conn.commit()
            print(f"{book}: {sum(len(c['verses']) for c in entry['chapters'])} verses")
    else:
        # USFM zip path — default, mirrors import_brenton but with USFM parser
        if use_html:
            url = _HTML_ZIP_URL
            # HTML path uses the same sentinel trick as import_brenton
            # (kept here as an else-branch so offline zip still works)
            from bs4 import BeautifulSoup  # lazy import
            zip_path = fetch_zip(url, Path(zip_path) if zip_path else None) if zip_path is None or not Path(zip_path).exists() else Path(zip_path)  # type: ignore
            html_zip = Path(zip_path)  # type: ignore
            with zipfile.ZipFile(html_zip) as z:
                names = set(z.namelist())
                # Iterate known Metanoia books; HTML chapter files zero-pad as GEN01.htm or PSA001.htm — same as Brenton
                # For brevity we walk the archive directly and map code->book
                for name in sorted(names):
                    if not name.lower().endswith(".htm"):
                        continue
                    # HTML files named like GEN01.htm — extract book code prefix
                    m = re.match(r"^([A-Z0-9]+?)(\d+)\.htm$", name, re.I)
                    if not m:
                        continue
                    code = m.group(1).upper()
                    chap = int(m.group(2))
                    book = USFM_CODE_TO_BOOK.get(code)
                    if not book or book == "__skip__":
                        continue
                    html = z.read(name).decode("utf-8", errors="replace")
                    # Same sentinel parse as import_brenton_septuagint.py:parse_chapter
                    soup = BeautifulSoup(html, "html.parser")
                    main = soup.find("div", class_="main")
                    if not main:
                        continue
                    for note in main.find_all("a", class_="notemark"):
                        note.decompose()
                    for span in main.find_all("span", class_="verse"):
                        vnum = span.get("id", "")[1:]
                        span.string = f"\x00{vnum}\x00"
                    parts = main.get_text().split("\x00")
                    verses: dict[int, str] = {}
                    for i in range(1, len(parts) - 1, 2):
                        try:
                            vn = int(parts[i])
                        except ValueError:
                            continue
                        vt = re.sub(r"\s+", " ", parts[i + 1]).strip()
                        if vt:
                            verses[vn] = vt
                    cur.executemany(
                        "INSERT OR REPLACE INTO verses (book, chapter, verse, text, version) VALUES (?, ?, ?, ?, ?)",
                        [(book, chap, vn, txt, _VERSION) for vn, txt in verses.items()],
                    )
                    total += len(verses)
            conn.commit()
        else:
            # Canonical USFM path
            zip_path = fetch_zip(_ZIP_URL, Path(zip_path) if zip_path else None) if zip_path is None or not Path(str(zip_path)).exists() else Path(str(zip_path))  # type: ignore
            uzip = Path(zip_path)  # type: ignore
            with zipfile.ZipFile(uzip) as z:
                for member in z.namelist():
                    if not member.lower().endswith(".usfm"):
                        continue
                    # Names like 02-GENeng-web.usfm or GEN.usfm — pull USFM code
                    base = Path(member).name
                    # Strip numeric prefix and suffix like "02-" and "eng-web.usfm"
                    m = re.search(r"([A-Z0-9]{2,4})", base.upper())
                    if not m:
                        continue
                    code = m.group(1)
                    # Prefer the \id code inside the file if it differs
                    raw = z.read(member).decode("utf-8", errors="replace")
                    id_m = re.search(r"^\\id\s+([A-Z0-9]+)", raw, re.M)
                    if id_m:
                        code = id_m.group(1).upper()
                    book = USFM_CODE_TO_BOOK.get(code)
                    if not book or book == "__skip__":
                        # Unknown/extracanonical — log and skip (e.g., GLO, 1ES before BIBLE_BOOKS extension)
                        continue
                    chapters = parse_usfm(raw)
                    for ch in chapters:
                        cur.executemany(
                            "INSERT OR REPLACE INTO verses (book, chapter, verse, text, version) VALUES (?, ?, ?, ?, ?)",
                            [(book, ch["chapter"], v["verse"], v["text"], _VERSION) for v in ch["verses"]],
                        )
                        total += len(ch["verses"])
                    ccount = len(chapters)
                    vcount = sum(len(c["verses"]) for c in chapters)
                    print(f"{book} ({code}): {ccount} ch, {vcount} vv")
            conn.commit()

    cur.execute("INSERT OR IGNORE INTO versions (slug, name) VALUES (?, ?)", (_VERSION, _VERSION_NAME))
    conn.commit()
    conn.close()
    # Touch manifest hint — split_db.py owns the real manifest, but leave a breadcrumb
    manifest = _REPO_ROOT / "data" / "db" / "manifest.json"
    if manifest.exists():
        print(f"\nNote: update {manifest} to include verses.web.db (primacy: comparison, filter: verses.version='WEB')")
    print(f"\nDone. {total} total WEB verses imported -> {out} (version='{_VERSION}')")
    print("Verify: sqlite3 data/db/verses.web.db \"SELECT version, COUNT(*) FROM verses GROUP BY version\"")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Import WEB (World English Bible, PD) into verses.web.db")
    ap.add_argument("zip", nargs="?", default=None, help="path to eng-web_usfm.zip (or _html.zip with --html)")
    ap.add_argument("--dir", dest="json_dir", default=None, help="per-book JSON dir (Fedora import-translation.js shape)")
    ap.add_argument("--out", default=str(_DEFAULT_OUT), help="output shard (default: data/db/verses.web.db)")
    ap.add_argument("--html", action="store_true", help="parse HTML zip instead of USFM (fallback, like Brenton)")
    args = ap.parse_args()
    import_web(zip_path=args.zip, json_dir=args.json_dir, out=args.out, use_html=args.html)
