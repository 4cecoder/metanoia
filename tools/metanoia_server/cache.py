import os
import sqlite3
from typing import Optional

from .core import CACHE_DIR, CACHE_DB, logger

MAX_CACHE_SIZE_MB = 1000
MAX_CACHE_AGE_DAYS = 30


class TTSCacheManager:
    def __init__(self, db_path: Optional[str] = None):
        path = db_path or CACHE_DB
        os.makedirs(os.path.dirname(path), exist_ok=True)
        self._conn = sqlite3.connect(path, check_same_thread=False, timeout=30)
        self._conn.row_factory = sqlite3.Row
        self._conn.execute("PRAGMA journal_mode=WAL")
        self._conn.execute("PRAGMA synchronous=NORMAL")
        self._init_db()

    @property
    def conn(self) -> sqlite3.Connection:
        return self._conn

    def _init_db(self):
        self.conn.execute("""
            CREATE TABLE IF NOT EXISTS tts_cache (
                key TEXT PRIMARY KEY,
                filename TEXT,
                text TEXT,
                voice TEXT,
                params_hash TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                last_accessed TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                access_count INTEGER DEFAULT 1,
                file_size INTEGER
            )
        """)
        self.conn.commit()

    def get(self, key: str) -> Optional[str]:
        cursor = self.conn.execute("SELECT filename FROM tts_cache WHERE key = ?", (key,))
        row = cursor.fetchone()
        if row:
            filename = row[0]
            if os.path.exists(filename):
                self.conn.execute(
                    "UPDATE tts_cache SET last_accessed = CURRENT_TIMESTAMP, access_count = access_count + 1 WHERE key = ?",
                    (key,),
                )
                self.conn.commit()
                return filename
            else:
                self.conn.execute("DELETE FROM tts_cache WHERE key = ?", (key,))
                self.conn.commit()
        return None

    def add(self, key: str, filename: str, text: str, voice: str, params_hash: str):
        file_size = os.path.getsize(filename)
        self.conn.execute(
            """INSERT OR REPLACE INTO tts_cache
            (key, filename, text, voice, params_hash, file_size)
            VALUES (?, ?, ?, ?, ?, ?)""",
            (key, filename, text, voice, params_hash, file_size),
        )
        self.conn.commit()
        self.prune()

    def close(self):
        self._conn.close()

    def prune(self):
        self.conn.execute(
            f"DELETE FROM tts_cache WHERE created_at < datetime('now', '-{MAX_CACHE_AGE_DAYS} days')"
        )
        total = self.conn.execute("SELECT COALESCE(SUM(file_size), 0) FROM tts_cache").fetchone()[0]
        limit = MAX_CACHE_SIZE_MB * 1024 * 1024
        if total > limit:
            rows = self.conn.execute(
                "SELECT key, filename, file_size FROM tts_cache ORDER BY last_accessed ASC LIMIT 50"
            ).fetchall()
            for row in rows:
                if os.path.exists(row["filename"]):
                    os.remove(row["filename"])
                self.conn.execute("DELETE FROM tts_cache WHERE key = ?", (row["key"],))
                total -= row["file_size"]
                if total <= int(limit * 0.8):
                    break
            self.conn.commit()
