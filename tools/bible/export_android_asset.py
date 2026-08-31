"""Exports data/bible.db (content only -- verses/interlinear/lexicon/etc,
see split_user_data_db.py) as a gzip-compressed Android asset,
mobile/app/src/main/assets/bible.db.gz.

The Android app (BibleDatabase.kt's seedContentDbFromAssetsIfNeeded())
decompresses this into its own per-device content DB on first run (or
after a CONTENT_DB_VERSION bump), completely separate from its personal-
data library DB -- see that class's doc comment for why the split matters
here specifically (a content update must never have a chance to touch
personal data).

Run this after any content change that should ship to Android (a new
interlinear/verse scrape, a schema migration) and bump
BibleDatabase.CONTENT_DB_VERSION in the same commit if existing installs
need to be reseeded, not just new ones.
"""

import gzip
import os
import shutil
import sqlite3
import tempfile

_SRC_DB = os.path.join(os.path.dirname(__file__), "..", "..", "data", "bible.db")
_DEST_GZ = os.path.join(
    os.path.dirname(__file__), "..", "..", "mobile", "app", "src", "main", "assets", "bible.db.gz"
)


def export():
    if not os.path.exists(_SRC_DB):
        raise SystemExit(f"{_SRC_DB} not found")

    with tempfile.TemporaryDirectory() as tmp:
        tmp_db = os.path.join(tmp, "bible.db")
        shutil.copy2(_SRC_DB, tmp_db)

        # VACUUM to compact (removes freed pages left over from all the
        # migrations/inserts/deletes this content DB has been through) --
        # smaller uncompressed file, smaller gzip, faster on-device copy.
        conn = sqlite3.connect(tmp_db)
        conn.execute("VACUUM")
        conn.close()

        os.makedirs(os.path.dirname(_DEST_GZ), exist_ok=True)
        with open(tmp_db, "rb") as f_in, gzip.open(_DEST_GZ, "wb", compresslevel=9) as f_out:
            shutil.copyfileobj(f_in, f_out)

    src_size = os.path.getsize(_SRC_DB) / (1024 * 1024)
    dest_size = os.path.getsize(_DEST_GZ) / (1024 * 1024)
    print(f"Exported {_SRC_DB} ({src_size:.1f} MB) -> {_DEST_GZ} ({dest_size:.1f} MB)")


if __name__ == "__main__":
    export()
