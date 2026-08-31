#!/usr/bin/env python3
"""
Split the monolithic data/bible.db into extremely-well sharded files.

  python tools/bible/split_db.py --source data/bible.db --out data/db

Idempotent & backward-compatible:
  - Leaves data/bible.db untouched.
  - Each shard is a fully valid SQLite file (VACUUM INTO + filter).
  - If run again, overwrites shards atomically.
  - Zig layer (src/bible_db.zig:openShardedDb) prefers shards if manifest exists,
    otherwise falls back to data/bible.db.

Shards mirror docs/DB_SHARDING.md manifest. See that doc for primacy/bundle rationale.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import sqlite3
import sys
import tempfile
import time


MANIFEST_VERSION = 1

SHARDS = [
    {
        "file": "core.db",
        "schema": "core",
        "primacy": "core",
        "license": "Mixed (PD + CC BY-SA where noted)",
        "tables": ["versions", "book_metadata", "chapter_summaries", "cross_references"],
        "keep_sql": None,  # copy whole tables (no filter)
    },
    {
        "file": "verses.lxxe.db",
        "schema": "en_lxxe",
        "primacy": "primary",
        "license": "PD (Brenton 1851) via eBible.org/eng-Brenton_usfm.zip",
        "source": "import_brenton_septuagint.py",
        "keep_sql": "verses.version='LXXE'",
        "tables": ["verses", "versions"],
    },
    {
        "file": "verses.nkjv.db",
        "schema": "en_nkjv",
        "primacy": "buried",
        "license": "Copyrighted (Thomas Nelson) — will be replaced by verses.web.db",
        "keep_sql": "verses.version='NKJV'",
        "tables": ["verses", "versions"],
        "bundle": False,
        "replaced_by": "verses.web.db",
    },
    {
        "file": "interlinear.lxx.db",
        "schema": "el_lxx",
        "primacy": "primary",
        "license": "Apostolic Polyglot via biblehub scrape (cache_lxx_interlinear.py)",
        "keep_sql": "interlinear.source='LXX'",
        "tables": ["interlinear"],
    },
    {
        "file": "interlinear.gnt.db",
        "schema": "el_gnt",
        "primacy": "primary",
        "license": "SBLGNT-adjacent GNT",
        "keep_sql": "interlinear.source='GNT'",
        "tables": ["interlinear"],
    },
    {
        "file": "interlinear.mt.db",
        "schema": "he_mt",
        "primacy": "buried",
        "license": "WLC Free via tanach.us",
        "keep_sql": "interlinear.source='MT'",
        "tables": ["interlinear"],
        "bundle": False,
    },
    {
        "file": "lexicon.db",
        "schema": "lex",
        "primacy": "shared",
        "license": "Strong's / lexicon composite",
        "tables": ["lexicon"],
        "keep_sql": None,
    },
]


def sha256(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def create_shard(source: pathlib.Path, out_dir: pathlib.Path, shard: dict) -> dict:
    fname = shard["file"]
    dest = out_dir / fname
    tmp = pathlib.Path(tempfile.mktemp(dir=str(out_dir), prefix=f".{fname}.tmp."))

    # VACUUM INTO copies the entire DB file's schema+data into tmp.
    # Requires that source is not in WAL mode with uncheckpointed frames — we checkpoint first.
    src = sqlite3.connect(str(source))
    try:
        src.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        src.execute(f"VACUUM INTO '{tmp}'")
    finally:
        src.close()

    conn = sqlite3.connect(str(tmp))
    try:
        cur = conn.cursor()

        # Keep only the tables/filter for this shard; drop/trim the rest.
        keep_tables = set(shard.get("tables") or [])

        # For filtered tables, delete rows not matching predicate.
        keep_sql = shard.get("keep_sql")
        if keep_sql:
            # keep_sql is of form "table.col='VAL'" — parse table name.
            table = keep_sql.split(".")[0]
            if table in keep_tables:
                # Delete non-matching rows from that table only.
                deleted = cur.execute(f"DELETE FROM {table} WHERE NOT ({keep_sql})").rowcount
                print(f"  {fname}: trimmed {table} where NOT ({keep_sql}) -> deleted {deleted}")
            keep_tables.discard(table)  # already handled
            # Delete entire tables not in keep_tables at all — drop them so shard stays minimal.
            # But for version-filtered shards we also want to drop the *other* table types entirely.
            # E.g., verses.lxxe.db should have ZERO interlinear/lexicon rows.
            for t in ["verses", "interlinear", "lexicon", "book_metadata", "chapter_summaries", "cross_references", "versions"]:
                if t not in shard.get("tables", []) and t not in [table]:
                    cur.execute(f"DELETE FROM {t}")
                    # Keep schema but empty is fine; VACUUM will shrink.
                    # Optionally DROP TABLE to make truly minimal — but keep empty for ATTACH UNION sympathy.
                    pass

        # For unfiltered shards (core.db, lexicon.db), delete tables not listed at all.
        else:
            # Delete every table not in keep_tables
            all_tables = ["verses", "interlinear", "lexicon", "book_metadata", "chapter_summaries", "cross_references", "versions"]
            for t in all_tables:
                if t not in keep_tables:
                    cur.execute(f"DELETE FROM {t}")

        conn.commit()
        conn.execute("VACUUM")
        conn.commit()

        # Row counts for manifest
        counts = {}
        for t in ["verses", "interlinear", "lexicon", "book_metadata", "chapter_summaries", "cross_references", "versions"]:
            try:
                counts[t] = cur.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
            except sqlite3.OperationalError:
                counts[t] = 0

    finally:
        conn.close()

    # Atomic move
    tmp.replace(dest)

    size = dest.stat().st_size
    digest = sha256(dest)
    print(f"  {fname}: {size / (1<<20):.1f} MB, sha256 {digest[:12]}..., counts {counts}")
    return {"file": fname, "bytes": size, "sha256": digest, "counts": counts, **{k: v for k, v in shard.items() if k not in ("file", "bytes", "sha256", "counts")}}


def main() -> None:
    ap = argparse.ArgumentParser(description="Split data/bible.db into sharded files (see docs/DB_SHARDING.md)")
    ap.add_argument("--source", default="data/bible.db", help="monolithic source DB")
    ap.add_argument("--out", default="data/db", help="output directory for shards")
    ap.add_argument("--manifest", default=None, help="manifest.json path (default: <out>/manifest.json)")
    args = ap.parse_args()

    source = pathlib.Path(args.source)
    out_dir = pathlib.Path(args.out)
    manifest_path = pathlib.Path(args.manifest) if args.manifest else out_dir / "manifest.json"

    if not source.exists():
        print(f"Source not found: {source}", file=sys.stderr)
        sys.exit(1)

    out_dir.mkdir(parents=True, exist_ok=True)

    print(f"Splitting {source} ({source.stat().st_size / (1<<20):.1f} MB) -> {out_dir}/ ({len(SHARDS)} shards)")

    shard_infos = []
    for shard in SHARDS:
        print(f"- {shard['file']} [{shard['primacy']}] keep {shard.get('keep_sql') or shard.get('tables')}")
        info = create_shard(source, out_dir, shard)
        shard_infos.append(info)

    # Default bundle = primacy primary+core+shared, bundle != False
    default_bundle = [s["file"] for s in shard_infos if s["primacy"] in ("core", "primary", "shared") and s.get("bundle", True) is not False]

    manifest = {
        "version": MANIFEST_VERSION,
        "generated": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "source": str(source),
        "source_bytes": source.stat().st_size,
        "source_sha256": sha256(source),
        "shards": shard_infos,
        "default_bundle": default_bundle,
        "notes": "NKJV shard is buried (bundle:false) and will be replaced by verses.web.db (WEB PD). See site/src/app/learn/english.",
    }

    tmp_manifest = manifest_path.with_suffix(".tmp.json")
    with tmp_manifest.open("w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, sort_keys=False)
        f.write("\n")
    tmp_manifest.replace(manifest_path)

    print(f"\nWrote {manifest_path}")
    print(f"Default bundle ({len(default_bundle)} files, ~{sum(s['bytes'] for s in shard_infos if s['file'] in default_bundle)/(1<<20):.0f} MB): {default_bundle}")
    print(f"All shards total ~{sum(s['bytes'] for s in shard_infos)/(1<<20):.0f} MB (vs monolith {source.stat().st_size/(1<<20):.0f} MB — delta is per-file page overhead)")
    print("Done. Zig can now ATTACH data/db/*.db as schemas; fallback to data/bible.db remains if manifest absent.")


if __name__ == "__main__":
    main()
