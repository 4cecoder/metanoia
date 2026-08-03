#!/usr/bin/env python3
"""
Real-world Bible scraper test suite.

Unlike unit tests with mocks, this actually hits the real scraping targets
(BibleGateway, BibleHub, Wikisource) and caches results. This allows:
1. Detection of real scraping failures (markup changes, rate limits, etc.)
2. Iterative debugging with cached results
3. Backoff and retry testing
4. Performance monitoring

Run with: python3 test_real_scrapers.py [--update-cache] [--verbose]
"""

import requests
from bs4 import BeautifulSoup
import json
import time
import os
import sys
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Tuple, Optional

# Cache directory
CACHE_DIR = Path(__file__).parent / ".cache" / "scrapers"
CACHE_DIR.mkdir(parents=True, exist_ok=True)

# User agent to mimic real requests
USER_AGENT = "Mozilla/5.0 (Linux; Android 15; Pixel 9 Pro) AppleWebKit/537.36"

# Rate limiting
MIN_REQUEST_DELAY = 1.0  # seconds between requests
last_request_time = 0

def rate_limit():
    """Ensure minimum delay between requests."""
    global last_request_time
    now = time.time()
    if now - last_request_time < MIN_REQUEST_DELAY:
        time.sleep(MIN_REQUEST_DELAY - (now - last_request_time))
    last_request_time = time.time()

def get_cached_data(cache_key: str) -> Optional[dict]:
    """Load cached scraping results."""
    cache_file = CACHE_DIR / f"{cache_key}.json"
    if cache_file.exists():
        with open(cache_file, 'r') as f:
            data = json.load(f)
            data['_cached_at'] = cache_file.stat().st_mtime
            return data
    return None

def save_cached_data(cache_key: str, data: dict):
    """Save scraping results to cache."""
    cache_file = CACHE_DIR / f"{cache_key}.json"
    with open(cache_file, 'w') as f:
        json.dump(data, f, indent=2)

def get_cached_html(cache_key: str) -> Optional[str]:
    """Load cached raw HTML."""
    cache_file = CACHE_DIR / f"{cache_key}.html"
    if cache_file.exists():
        with open(cache_file, 'r', encoding='utf-8') as f:
            return f.read()
    return None

def save_cached_html(cache_key: str, html: str):
    """Save raw HTML to cache."""
    cache_file = CACHE_DIR / f"{cache_key}.html"
    with open(cache_file, 'w', encoding='utf-8') as f:
        f.write(html)

def test_biblegateway_chapter(book: str, chapter: int, version: str = "NKJV") -> dict:
    """Test BibleGateway chapter scraping."""
    cache_key = f"biblegateway_{book}_{chapter}_{version}"
    cached_html = get_cached_html(cache_key)

    # Only fetch if explicitly requested or no cache exists
    if not cached_html or '--update-cache' in sys.argv:
        rate_limit()

        url = f"https://www.biblegateway.com/passage/?search={book}+{chapter}&version={version}&interface=print"
        print(f"Fetching: {url}")

        response = requests.get(url, headers={"User-Agent": USER_AGENT}, timeout=30)

        if response.status_code != 200:
            return {
                'url': url,
                'status_code': response.status_code,
                'success': False,
                'error': f'HTTP {response.status_code}'
            }

        cached_html = response.text
        save_cached_html(cache_key, cached_html)
        print(f"Cached {len(cached_html)} bytes")
    else:
        print(f"Using cached HTML ({len(cached_html)} bytes)")

    # Parse cached HTML
    soup = BeautifulSoup(cached_html, 'html.parser')

    result = {
        'url': f"https://www.biblegateway.com/passage/?search={book}+{chapter}&version={version}&interface=print",
        'status_code': 200,
        'success': True,
        'content_length': len(cached_html),
        'html_snippet': cached_html[:500] if len(cached_html) < 500 else cached_html[:500] + '...',
        'verses': [],
        'debug': {
            'passage_text_divs': len(soup.select('div.passage-text')),
            'span_text_elements': len(soup.select('div.passage-text span.text')),
            'all_spans': len(soup.select('span')),
            'h1_elements': len(soup.select('h1')),
        }
    }

    # Remove headers
    for header in soup.select('h1, h2, h3, h4, h5, h6'):
        header.decompose()

    # Try to extract verses
    for span in soup.select('div.passage-text span.text'):
        import re
        classes = span.get('class', [])
        if isinstance(classes, list):
            class_str = ' '.join(classes)
        else:
            class_str = str(classes) if classes else ''
        verse_match = re.search(r'-(\d+)$', class_str)
        if verse_match:
            verse_num = int(verse_match.group(1))
            # Remove verse number markers
            for sup in span.select('sup, span.chapternum, span.versenum'):
                sup.decompose()
            text = span.get_text(strip=True)
            result['verses'].append({'verse': verse_num, 'text': text})

    result['verse_count'] = len(result['verses'])
    save_cached_data(cache_key, result)
    return result

def test_biblehub_interlinear(book: str, chapter: int) -> dict:
    """Test BibleHub interlinear scraping."""
    cache_key = f"biblehub_interlinear_{book}_{chapter}"
    cached = get_cached_data(cache_key)

    if cached and not '--update-cache' in sys.argv:
        return cached

    rate_limit()

    # Convert book name to URL slug
    book_slug = book.lower().replace(' ', '')
    if 'songof' in book_slug:
        book_slug = 'songs'
    import re
    book_slug = re.sub(r'^(\d+)([a-z]+)$', r'\1_\2', book_slug)

    url = f"https://biblehub.com/interlinear/{book_slug}/{chapter}.htm"
    print(f"Fetching: {url}")

    response = requests.get(url, headers={"User-Agent": USER_AGENT}, timeout=30)

    result = {
        'url': url,
        'status_code': response.status_code,
        'success': response.status_code == 200,
        'content_length': len(response.text),
        'words': []
    }

    if response.status_code == 200:
        soup = BeautifulSoup(response.text, 'html.parser')
        current_verse = 0
        word_idx = 0

        for element in soup.select('table[class*=tablefloat], div.interlinear'):
            v_span = element.select('span.reftop3, span.reftop, a.vref')
            if v_span:
                v_txt = ''.join(c for c in v_span[0].get_text() if c.isdigit())
                if v_txt:
                    n_v = int(v_txt)
                    if n_v != current_verse:
                        current_verse = n_v
                        word_idx = 0

            if current_verse > 0:
                orig = element.select('span.greek, span.heb, span.hebrew')
                if orig:
                    orig_text = orig[0].get_text(strip=True)
                    if orig_text:
                        strongs_el = element.select('span.pos, span.strongs, a[href*="/strongs/"]')
                        strongs = strongs_el[0].get_text(strip=True) if strongs_el else ''
                        strongs = ''.join(c for c in strongs if c.isdigit())

                        trans_el = element.select('span.eng')
                        trans = trans_el[0].get_text(strip=True) if trans_el else ''

                        result['words'].append({
                            'verse': current_verse,
                            'word_index': word_idx,
                            'original': orig_text,
                            'translation': trans,
                            'strongs': strongs
                        })
                        word_idx += 1

    result['word_count'] = len(result['words'])
    save_cached_data(cache_key, result)
    return result

def test_wikisource_apocrypha(book: str, chapter: int) -> dict:
    """Test Wikisource Apocrypha scraping."""
    cache_key = f"wikisource_{book}_{chapter}"
    cached = get_cached_data(cache_key)

    if cached and not '--update-cache' in sys.argv:
        return cached

    rate_limit()

    # Map book names to Wikisource slugs
    slugs = {
        "Tobit": "Tobit",
        "Judith": "Judith",
        "Wisdom": "Wisdom_of_Solomon",
        "Sirach": "Ecclesiasticus"
    }

    slug = slugs.get(book)
    if not slug:
        return {'error': f'Unknown book: {book}', 'success': False}

    url = f"https://en.wikisource.org/wiki/Bible_(King_James)/{slug}"
    print(f"Fetching: {url}")

    response = requests.get(url, headers={"User-Agent": USER_AGENT}, timeout=30)

    result = {
        'url': url,
        'status_code': response.status_code,
        'success': response.status_code == 200,
        'content_length': len(response.text),
        'verses': []
    }

    if response.status_code == 200:
        soup = BeautifulSoup(response.text, 'html.parser')
        prefix = f"{chapter}:"

        for p in soup.select('p:has(span.wst-verse)'):
            span = p.select_one('span.wst-verse')
            if span:
                span_id = span.get('id', '')
                if span_id.startswith(prefix):
                    try:
                        verse_num = int(span_id.split(':')[1])
                        sup_text = span.select_one('sup')
                        if sup_text:
                            sup_text.decompose()
                        text = p.get_text(strip=True)
                        result['verses'].append({'verse': verse_num, 'text': text})
                    except (ValueError, IndexError):
                        continue

    result['verse_count'] = len(result['verses'])
    save_cached_data(cache_key, result)
    return result

def run_test_suite():
    """Run comprehensive real-world scraper tests."""
    tests = [
        # BibleGateway tests (OT books)
        ("BibleGateway Genesis 1", lambda: test_biblegateway_chapter("Genesis", 1)),
        ("BibleGateway Psalms 23", lambda: test_biblegateway_chapter("Psalms", 23)),
        ("BibleGateway Isaiah 53", lambda: test_biblegateway_chapter("Isaiah", 53)),

        # BibleGateway tests (NT books)
        ("BibleGateway Matthew 1", lambda: test_biblegateway_chapter("Matthew", 1)),
        ("BibleGateway John 3", lambda: test_biblegateway_chapter("John", 3)),
        ("BibleGateway Romans 8", lambda: test_biblegateway_chapter("Romans", 8)),

        # BibleHub interlinear tests
        ("BibleHub Genesis 1", lambda: test_biblehub_interlinear("Genesis", 1)),
        ("BibleHub John 1", lambda: test_biblehub_interlinear("John", 1)),

        # Wikisource Apocrypha tests
        ("Wikisource Tobit 1", lambda: test_wikisource_apocrypha("Tobit", 1)),
        ("Wikisource Wisdom 1", lambda: test_wikisource_apocrypha("Wisdom", 1)),
    ]

    results = []

    for test_name, test_func in tests:
        print(f"\n{'='*60}")
        print(f"Running: {test_name}")
        print('='*60)

        try:
            result = test_func()
            result['test_name'] = test_name
            result['timestamp'] = datetime.now().isoformat()

            if result.get('success'):
                print(f"✓ SUCCESS")
                if 'verse_count' in result:
                    print(f"  Verses found: {result['verse_count']}")
                if 'word_count' in result:
                    print(f"  Words found: {result['word_count']}")
            else:
                print(f"✗ FAILED")
                if 'error' in result:
                    print(f"  Error: {result['error']}")
                if 'status_code' in result:
                    print(f"  HTTP {result['status_code']}")

            results.append(result)

        except Exception as e:
            print(f"✗ EXCEPTION: {e}")
            results.append({
                'test_name': test_name,
                'success': False,
                'error': str(e),
                'exception': type(e).__name__
            })

    # Save summary
    summary_file = CACHE_DIR / "test_summary.json"
    with open(summary_file, 'w') as f:
        json.dump(results, f, indent=2)

    print(f"\n{'='*60}")
    print("SUMMARY")
    print('='*60)
    success_count = sum(1 for r in results if r.get('success'))
    total_count = len(results)
    print(f"Passed: {success_count}/{total_count}")

    failed = [r for r in results if not r.get('success')]
    if failed:
        print(f"\nFailed tests:")
        for r in failed:
            print(f"  - {r['test_name']}: {r.get('error', r.get('exception', 'Unknown'))}")

    return success_count == total_count

if __name__ == '__main__':
    success = run_test_suite()
    sys.exit(0 if success else 1)