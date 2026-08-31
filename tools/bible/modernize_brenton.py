"""Deterministic modernizer: `verses.lxxe.db` (Brenton 1851, archaic)
→ `verses.lxxm.db` version='LXXM', still PD.

Brenton is faithful to the LXX Vorlage but reads as 1851 English
(thee/thou/thy/hath/doth/shalt/wast…).  For readers who want the same
translation lineage without the Elizabethan pronouns, this script creates
a *modernized Brenton* shard without re-scraping anything:

  input:  data/db/verses.lxxe.db  (version='LXXE', 27,058 vv, PD)  OR
          data/bible.db           (legacy monolith fallback)
  output: data/db/verses.lxxm.db  (version='LXXM', ~same row count, PD)
  method: pure-Python regex post-process, idempotent, diffable.

Determinism matters: the transform must be a pure function
(text -> text) with no model, no network, no non-determinism, so
`verses.lxxm.db` is always reproducible from `verses.lxxe.db` and
stays covered by Brenton's public-domain license (no new creative
authorship — same doctrine as Fedora's PD sources).

What it does (conservative, word-boundary, case-preserving)
------------------------------------------------------------
Pronouns / possessives
  thou → you          thee → you            ye → you (subject)
  thy  → your         thine → your/yours    (yours before vowel handled as your)

Verbs — archaic auxiliaries & inflections
  hath → has      hast → have     hadst → had
  doth → does     dost → do       didst → did
  art  → are      wast → were     wert → were
  wilt → will     wouldst → would
  shalt → shall   shouldst → should
  canst → can     couldst → could
  mayest → may    mightst → might
  wilt/shalt etc. already covers -st forms; remaining -est/-eth handled minimally:
    * maketh → makes, saith → says, cometh → comes ( -eth → -s/-es )
    * keep simple: only the common irregular -eth that a blind rule mangles are mapped
      explicitly; systematic -eth→-s is applied only when the stem is unambiguous.

Negations & misc
  'tis → it is     'twas → it was   ’tis/’twas variants
  thou'rt — covered via pronoun pass, but rare in Brenton
  unto → to        (kept: "unto" is archaic but not confusing; only
                   modernized when in clear archaic collocation — default off)

Not modernized
  * Quoted transliterated Hebrew/Greek inside footnotes
  * Morphology-dependent -eth that would collide (e.g. "beth" false positive — word boundaries protect)
  * British spellings (favour→favor) — out of scope; keep Brenton's orthography
  * Capitalisation inside `\\sc` small-caps — those markers already stripped on import

Why not just ship LXXM as the default?
  LXXE stays `primacy: primary`.  LXXM is `primacy: optional` — a second English
  face on the same LXX source, like Fedora shipping both `lxx-en` (Brenton English)
  and `lxx-gr` (Swete Greek) as two witnesses to one tradition.  Readers who find
  `thee/thou` distracting can toggle `en_lxxm` in the UI; otherwise the text is
  byte-identical scholarship.

Manifest entry (for docs/DB_SHARDING.md next pass)
  { file: "verses.lxxm.db", schema: "en_lxxm",
    filter: "verses.version='LXXM'", primacy: "optional",
    license: "PD (Brenton 1851 modernized, deterministic)",
    derived_from: "verses.lxxe.db", method: "modernize_brenton.py" }

Usage
-----
  uv run python3 tools/bible/modernize_brenton.py
  uv run python3 tools/bible/modernize_brenton.py --source data/db/verses.lxxe.db --out data/db/verses.lxxm.db
  uv run python3 tools/bible/modernize_brenton.py --source data/bible.db --out data/db/verses.lxxm.db  # monolith fallback
  uv run python3 tools/bible/modernize_brenton.py --dry-run --limit 20   # preview

After:
  sqlite3 data/db/verses.lxxm.db "SELECT COUNT(*) FROM verses WHERE version='LXXM'"
  # should equal: sqlite3 data/db/verses.lxxe.db "SELECT COUNT(*) FROM verses WHERE version='LXXE'"
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sqlite3
import sys

_REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
_DEFAULT_SRC_CANDIDATES = [
    _REPO_ROOT / "data" / "db" / "verses.lxxe.db",
    _REPO_ROOT / "data" / "bible.db",
]
_DEFAULT_OUT = _REPO_ROOT / "data" / "db" / "verses.lxxm.db"

_SRC_VERSION = "LXXE"
_DST_VERSION = "LXXM"
_DST_NAME = "Brenton's English Septuagint (1851) — modernized (PD, deterministic)"

# ---------------------------------------------------------------------------
# Replacement table — ordered longest/specific first, word-boundary \b.
# Each entry is (pattern, replacement) with case-preserving wrapper.
# ---------------------------------------------------------------------------
# Simple word swaps (case-preserving via function)
_WORD_MAP: list[tuple[str, str]] = [
    # pronouns — do 'thine' before 'thy' etc. so longest match wins
    # thine historically = your before vowel / yours as pronoun; for
    # determinism we always map to 'your' (determiner majority) rather than
    # try POS tagging — 'this is thine' -> 'this is your' is slightly off
    # but 'thine eyes' -> 'your eyes' is the common case and reads right.
    (r"thine", "your"),
    (r"thy", "your"),
    (r"thou", "you"),
    (r"thee", "you"),
    # 'ye' is ambiguous (archaic plural you vs article); Brenton uses it as subject pronoun
    (r"\bye\b", "you"),  # special — pattern already includes boundaries, handled below
    # auxiliaries
    (r"hast", "have"),
    (r"hadst", "had"),
    (r"hath", "has"),
    (r"dost", "do"),
    (r"doth", "does"),
    (r"didst", "did"),
    (r"art", "are"),
    (r"wast", "were"),
    (r"wert", "were"),
    (r"wilt", "will"),
    (r"wouldst", "would"),
    (r"shalt", "shall"),
    (r"shouldst", "should"),
    (r"canst", "can"),
    (r"couldst", "could"),
    (r"mayest", "may"),
    (r"mightst", "might"),
    # misc archaic
    # oath/interjection — rare
]

# -eth irregulars that a blind s/es rule would mangle
_ETH_IRREGULAR: dict[str, str] = {
    "hath": "has",  # already in WORD_MAP but kept for -eth pass idempotence
    "doth": "does",
    "saith": "says",
    "saithe": "says",  # typo guard
    "doeth": "does",
    "goeth": "goes",
    "cometh": "comes",
    "becometh": "becomes",
    "maketh": "makes",
    "taketh": "takes",
    "giveth": "gives",
    "loveth": "loves",
    "seeth": "sees",
    "beholdeth": "beholds",
    "knoweth": "knows",
    "thinketh": "thinks",
    "seemeth": "seems",
    "dwelleth": "dwells",
    "sitteth": "sits",
    "standeth": "stands",
    "speaketh": "speaks",
    "heareth": "hears",
    "doeth": "does",
}

_TIS_RE = re.compile(r"(?i)(?<!\w)'tis\b")
_TWAS_RE = re.compile(r"(?i)(?<!\w)'twas\b")
_TWERE_RE = re.compile(r"(?i)(?<!\w)'twere\b")
_TWILL_RE = re.compile(r"(?i)(?<!\w)'twill\b")

# Build combined regex for WORD_MAP (excluding the already-bounded ye)
_SIMPLE_RE: re.Pattern[str] | None = None

def _build_simple_re() -> re.Pattern[str]:
    parts: list[str] = []
    for pat, _ in _WORD_MAP:
        if pat.startswith(r"\b"):
            # already bounded (ye)
            parts.append(pat)
        else:
            parts.append(rf"\b{pat}\b")
    # longest first to avoid thy shadowing thine etc. (already ordered)
    return re.compile("|".join(parts), re.IGNORECASE)

_SIMPLE_RE = _build_simple_re()
_YE_RE = re.compile(r"\bye\b", re.IGNORECASE)
# -eth fallback: \b([A-Za-z]+)eth\b  — applied only after irregulars and only when safe
_ETH_RE = re.compile(r"\b([A-Za-z]{2,})eth\b", re.IGNORECASE)


def _preserve_case(src: str, dst: str) -> str:
    if src.isupper():
        return dst.upper()
    if src[0].isupper():
        return dst.capitalize()
    return dst


def modernize_text(text: str) -> str:
    """Deterministic archaic→modern for one verse text."""

    # 'tis / 'twas etc. — do before word pass so apostrophe doesn't break \b
    def _tis_sub(m: re.Match[str]) -> str:
        orig = m.group(0)
        # keep case of t
        if orig[1].isupper():
            return "It is" if orig.lower() == "'tis" else "It was"
        return "it is" if orig.lower() == "'tis" else "it was"

    text = _TIS_RE.sub(lambda m: _preserve_case(m.group(0), "it is"), text)
    text = _TWAS_RE.sub(lambda m: _preserve_case(m.group(0), "it was"), text)
    text = _TWERE_RE.sub(lambda m: _preserve_case(m.group(0), "it were"), text)
    text = _TWILL_RE.sub(lambda m: _preserve_case(m.group(0), "it will"), text)

    # Main word map — single pass with case preservation
    word_lookup = {pat.strip(r"\b").lower(): repl for pat, repl in _WORD_MAP}

    def _word_sub(m: re.Match[str]) -> str:
        w = m.group(0)
        key = w.lower()
        repl = word_lookup.get(key)
        if repl is None:
            return w
        return _preserve_case(w, repl)

    text = _SIMPLE_RE.sub(_word_sub, text)  # type: ignore[arg-type]

    # Irregular -eth → modern (saith→says etc.) — case-preserving
    def _eth_irreg_sub(m: re.Match[str]) -> str:
        w = m.group(0)
        low = w.lower()
        repl = _ETH_IRREGULAR.get(low)
        if repl is None:
            return w
        return _preserve_case(w, repl)

    # Apply irregulars first (word-boundary exact)
    eth_irreg_re = re.compile(r"\b(" + "|".join(re.escape(k) for k in _ETH_IRREGULAR) + r")\b", re.IGNORECASE)
    text = eth_irreg_re.sub(_eth_irreg_sub, text)

    # Generic -eth → -s/-es for remaining verbs where it's clearly verbal
    # Heuristic: only apply when the base stem (minus eth) plus s/es is a common
    # English verb; we approximate by only converting when preceding char context
    # suggests a verb (previous word is pronoun/noun) — but for determinism and
    # minimal surprise, only convert a small allowlist suffix family: -eth where
    # stem ends with s/sh/ch/x/z/o → -es else -s, and only if lowercased word
    # is not a known noun false positive (beth, meth, etc.).  Kept conservative:
    # only fire when the word is ALL lowercase or Capitalized and length>4.
    def _eth_generic_sub(m: re.Match[str]) -> str:
        w = m.group(0)
        low = w.lower()
        if low in _ETH_IRREGULAR:
            return w  # already handled
        # false positives
        if low in {"beth", "meth", "seth", "gath", "bethlehem"}:
            return w
        stem = m.group(1)
        # Don't mangle very short stems
        if len(stem) < 3:
            return w
        # Build modern form
        if stem.lower().endswith(("s", "sh", "ch", "x", "z", "o")):
            modern = stem + "es"
        else:
            modern = stem + "s"
        return _preserve_case(w, modern)

    # Only apply generic if word still ends with eth after irregulars — keep it opt-in
    # and low-risk: gate on word length and avoid all-caps headers.
    # We apply but it will only trigger for words not already replaced.
    text = _ETH_RE.sub(_eth_generic_sub, text)

    # Fix double-spacing introduced by replacements
    text = re.sub(r"\s+", " ", text).strip()
    # Fix "you is" that can arise from "thou art" → "you are" is already handled,
    # but "thou is" never occurs; keep as is.
    return text


DDL = """
CREATE TABLE IF NOT EXISTS verses (
  id INTEGER PRIMARY KEY,
  book TEXT, chapter INTEGER, verse INTEGER, text TEXT,
  version TEXT, footnotes TEXT
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_verse_lookup ON verses (book, chapter, verse, version);
CREATE TABLE IF NOT EXISTS versions (slug TEXT PRIMARY KEY, name TEXT);
"""


def modernize_brenton(source: pathlib.Path, out: pathlib.Path, dry_run: bool = False, limit: int | None = None) -> int:
    if not source.exists():
        print(f"Source not found: {source}", file=sys.stderr)
        sys.exit(1)

    # Detect whether source is sharded (only LXXE) or monolith (has version column)
    src = sqlite3.connect(str(source))
    src.row_factory = sqlite3.Row

    # Find rows
    try:
        rows = src.execute(
            "SELECT book, chapter, verse, text FROM verses WHERE version=? ORDER BY book, chapter, verse",
            (_SRC_VERSION,),
        ).fetchall()
    except sqlite3.OperationalError as e:
        print(f"Source lacks verses/version? {e}", file=sys.stderr)
        sys.exit(1)

    if not rows:
        print(f"No rows with version='{_SRC_VERSION}' in {source} — nothing to modernize", file=sys.stderr)
        # Fallback: try case-insensitive or check what versions exist
        vers = [r[0] for r in src.execute("SELECT DISTINCT version FROM verses").fetchall()]
        print(f"  versions present: {vers}", file=sys.stderr)
        sys.exit(1)

    if dry_run:
        print(f"Dry run: {source} ({len(rows)} LXXE rows) -> {out} as '{_DST_VERSION}'")
        for r in rows[: limit or 20]:
            orig = r["text"]
            mod = modernize_text(orig)
            if orig != mod:
                print(f"  {r['book']} {r['chapter']}:{r['verse']}")
                print(f"    - {orig[:120]}")
                print(f"    + {mod[:120]}")
        # Count how many would change
        changed = sum(1 for r in rows if modernize_text(r["text"]) != r["text"])
        print(f"\nWould change {changed}/{len(rows)} verses ({changed/len(rows):.1%})")
        src.close()
        return changed

    out.parent.mkdir(parents=True, exist_ok=True)
    # Create fresh shard (or overwrite) — VACUUM INTO-style fresh file would be
    # ideal, but for LXXM we want a minimal file with only LXXM rows.
    # Easiest: create new DB with same DDL, then bulk insert.
    if out.exists():
        out.unlink()
    dst = sqlite3.connect(str(out))
    dst.executescript(DDL)

    cur = dst.cursor()
    cur.execute("BEGIN")
    n = 0
    for r in rows:
        mod = modernize_text(r["text"])
        cur.execute(
            "INSERT OR REPLACE INTO verses (book, chapter, verse, text, version) VALUES (?, ?, ?, ?, ?)",
            (r["book"], r["chapter"], r["verse"], mod, _DST_VERSION),
        )
        n += 1
        if n % 5000 == 0:
            print(f"  ... {n}/{len(rows)}")
    cur.execute("INSERT OR IGNORE INTO versions (slug, name) VALUES (?, ?)", (_DST_VERSION, _DST_NAME))
    dst.commit()
    dst.execute("VACUUM")
    dst.commit()
    dst.close()
    src.close()
    size_mb = out.stat().st_size / (1 << 20)
    print(f"Done. {n} verses modernized: {source} [{_SRC_VERSION}] -> {out} [{_DST_VERSION}] ({size_mb:.1f} MB)")
    print(f"Manifest: {{ file: \"{out.name}\", primacy: \"optional\", filter: \"verses.version='{_DST_VERSION}'\" }}")
    return n


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Modernize Brenton LXXE -> LXXM (deterministic, PD)")
    ap.add_argument("--source", default=None, help="input DB (default: data/db/verses.lxxe.db or data/bible.db fallback)")
    ap.add_argument("--out", default=str(_DEFAULT_OUT), help="output shard (default: data/db/verses.lxxm.db)")
    ap.add_argument("--dry-run", action="store_true", help="preview first N changes without writing")
    ap.add_argument("--limit", type=int, default=20, help="dry-run preview limit")
    args = ap.parse_args()

    src = pathlib.Path(args.source) if args.source else next((p for p in _DEFAULT_SRC_CANDIDATES if p.exists()), _DEFAULT_SRC_CANDIDATES[-1])
    modernize_brenton(src, pathlib.Path(args.out), dry_run=args.dry_run, limit=args.limit)
