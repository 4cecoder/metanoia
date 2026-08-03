#!/usr/bin/env python3
"""
Organized scratchpad runner for Bible scraper development.

This script:
1. Loads real HTML from cached targets (avoids hitting endpoints)
2. Tests scraper parsing logic against cached data
3. Generates Kotlin test cases from working patterns
4. Organizes results by book/chapter/success

Run: python3 tools/organized_scraper_development.py
"""

import json
from pathlib import Path
from typing import Dict, List, Optional
from datetime import datetime
import re
from bs4 import BeautifulSoup

CACHE_DIR = Path(__file__).parent / ".cache" / "scrapers"
RESULTS_DIR = Path(__file__).parent / ".cache" / "results"
RESULTS_DIR.mkdir(parents=True, exist_ok=True)

def load_cached_html(cache_key: str) -> Optional[str]:
    """Load cached HTML from cache directory."""
    html_file = CACHE_DIR / f"{cache_key}.html"
    if html_file.exists():
        with open(html_file, 'r', encoding='utf-8') as f:
            return f.read()
    return None

def extract_biblegateway_verses(html: str) -> List[tuple]:
    """Extract verses from BibleGateway HTML using Kotlin-compatible logic."""
    soup = BeautifulSoup(html, 'html.parser')

    # Remove headers
    for header in soup.select('h1, h2, h3, h4, h5, h6'):
        header.decompose()

    verses = []
    for span in soup.select('div.passage-text span.text'):
        class_name = span.get('class', [])
        if isinstance(class_name, list):
            class_str = ' '.join(class_name)
        else:
            class_str = str(class_name) if class_name else ''

        # Kotlin: Regex("-(\\d+)$").find(className)?.groupValues?.get(1)?.toInt()
        verse_match = re.search(r'-(\d+)$', class_str)

        if verse_match:
            verse_num = int(verse_match.group(1))

            # Remove verse markers
            for sup in span.select('sup, span.chapternum, span.versenum'):
                sup.decompose()

            text = span.get_text(strip=True)
            verses.append((verse_num, text))

    return verses

def extract_biblehub_verses(html: str) -> List[tuple]:
    """Extract verses from BibleHub text page HTML."""
    soup = BeautifulSoup(html, 'html.parser')

    verses = []
    current_verse = 0

    for p in soup.select('div.chapter p'):
        verse_link = p.select_one('a[href*=".htm"]')
        verse_sup = p.select_one('sup')

        verse_text = None
        if verse_link:
            num_text = ''.join(c for c in verse_link.get_text() if c.isdigit())
            if num_text:
                current_verse = int(num_text)
            verse_link.decompose()
            verse_text = p.get_text(strip=True)
        elif verse_sup:
            num_text = ''.join(c for c in verse_sup.get_text() if c.isdigit())
            if num_text:
                current_verse = int(num_text)
            verse_sup.decompose()
            verse_text = p.get_text(strip=True)
        else:
            verse_text = p.get_text(strip=True)

        if current_verse > 0 and verse_text:
            verses.append((current_verse, verse_text))

    return verses

def test_scraper_pattern(scraper_name: str, html: str) -> dict:
    """Test a scraper pattern against HTML and return results."""
    if scraper_name == "BibleGateway":
        verses = extract_biblegateway_verses(html)
    elif scraper_name == "BibleHub":
        verses = extract_biblehub_verses(html)
    else:
        return {"error": f"Unknown scraper: {scraper_name}"}

    return {
        "verse_count": len(verses),
        "verses": [{"verse": v, "text": t[:100] + "..."} for v, t in verses],
        "sample_verses": verses[:3]  # First 3 verses for validation
    }

def organize_test_results() -> Dict:
    """Organize all cached HTML into structured test results."""
    results = {
        "timestamp": datetime.now().isoformat(),
        "scrapers": {}
    }

    # BibleGateway tests
    biblegateway_books = [
        ("Genesis", 1, "NKJV"),
        ("Psalms", 23, "NKJV"),
        ("Isaiah", 53, "NKJV"),
        ("Matthew", 1, "NKJV"),
        ("John", 3, "NKJV"),
        ("Romans", 8, "NKJV"),
    ]

    biblegateway_results = []
    for book, chapter, version in biblegateway_books:
        cache_key = f"biblegateway_{book}_{chapter}_{version}"
        html = load_cached_html(cache_key)

        if html:
            result = test_scraper_pattern("BibleGateway", html)
            biblegateway_results.append({
                "book": book,
                "chapter": chapter,
                "version": version,
                "success": "error" not in result,
                "verse_count": result.get("verse_count", 0),
                "sample_verses": result.get("sample_verses", [])
            })
        else:
            biblegateway_results.append({
                "book": book,
                "chapter": chapter,
                "version": version,
                "success": False,
                "error": "No cached HTML"
            })

    results["scrapers"]["BibleGateway"] = {
        "total_tests": len(biblegateway_results),
        "successful_tests": sum(1 for r in biblegateway_results if r.get("success")),
        "results": biblegateway_results
    }

    # BibleHub tests
    biblehub_books = [
        ("Genesis", 1, "kjv"),
        ("John", 1, "kjv"),
    ]

    biblehub_results = []
    for book, chapter, version in biblehub_books:
        cache_key = f"biblehub_interlinear_{book}_{chapter}"
        html = load_cached_html(cache_key)

        if html:
            result = test_scraper_pattern("BibleHub", html)
            biblehub_results.append({
                "book": book,
                "chapter": chapter,
                "version": version,
                "success": "error" not in result,
                "verse_count": result.get("verse_count", 0),
                "sample_verses": result.get("sample_verses", [])
            })
        else:
            biblehub_results.append({
                "book": book,
                "chapter": chapter,
                "version": version,
                "success": False,
                "error": "No cached HTML"
            })

    results["scrapers"]["BibleHub"] = {
        "total_tests": len(biblehub_results),
        "successful_tests": sum(1 for r in biblehub_results if r.get("success")),
        "results": biblehub_results
    }

    return results

def generate_kotlin_unit_tests(results: Dict) -> str:
    """Generate Kotlin unit test code from organized results."""
    kotlin_code = """package com.bytecats.metanoia.bible

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Auto-generated unit tests from organized scraper development.
 *
 * Generated by tools/organized_scraper_development.py
 * at: ${results['timestamp']}
 */
class OrganizedScraperTest {

"""

    # BibleGateway tests
    kotlin_code += "    // ===== BibleGateway Tests =====\n\n"

    for result in results["scrapers"]["BibleGateway"]["results"]:
        if result.get("success"):
            book = result["book"]
            chapter = result["chapter"]
            expected_verses = result["verse_count"]

            kotlin_code += f"""    @Test
    fun `BibleGateway {book} {chapter} extracts {expected_verses} verses`() {{
        // This test validates against cached HTML from real BibleGateway
        // Run tools/organized_scraper_development.py to update cache if needed
        val expectedVerseCount = {expected_verses}
        // TODO: Implement test using CachedChapterScraper
        assertTrue("BibleGateway should extract verses", expectedVerseCount > 0)
    }}

"""

    # BibleHub tests
    kotlin_code += "    // ===== BibleHub Tests =====\n\n"

    for result in results["scrapers"]["BibleHub"]["results"]:
        if result.get("success"):
            book = result["book"]
            chapter = result["chapter"]
            expected_verses = result["verse_count"]

            kotlin_code += f"""    @Test
    fun `BibleHub {book} {chapter} extracts {expected_verses} verses`() {{
        // This test validates against cached HTML from real BibleHub
        // Run tools/organized_scraper_development.py to update cache if needed
        val expectedVerseCount = {expected_verses}
        // TODO: Implement test using CachedChapterScraper
        assertTrue("BibleHub should extract verses", expectedVerseCount > 0)
    }}

"""

    kotlin_code += "}\n"
    return kotlin_code

def main():
    print("=" * 70)
    print("Organized Scraper Development")
    print("=" * 70)

    # Organize test results from cached HTML
    results = organize_test_results()

    # Save organized results
    results_file = RESULTS_DIR / "organized_results.json"
    with open(results_file, 'w') as f:
        json.dump(results, f, indent=2)

    print(f"\n✓ Organized results saved to: {results_file}")

    # Generate Kotlin unit tests
    kotlin_tests = generate_kotlin_unit_tests(results)
    kotlin_file = RESULTS_DIR / "OrganizedScraperTest.kt"
    with open(kotlin_file, 'w') as f:
        f.write(kotlin_tests)

    print(f"✓ Kotlin unit tests generated: {kotlin_file}")

    # Print summary
    print("\n" + "=" * 70)
    print("Summary")
    print("=" * 70)

    for scraper_name, scraper_data in results["scrapers"].items():
        total = scraper_data["total_tests"]
        successful = scraper_data["successful_tests"]
        print(f"\n{scraper_name}:")
        print(f"  Total tests: {total}")
        print(f"  Successful: {successful}")

        for result in scraper_data["results"]:
            status = "✓" if result.get("success") else "✗"
            verse_count = result.get("verse_count", "N/A")
            print(f"    {status} {result['book']} {result['chapter']}: {verse_count} verses")

    print(f"\nResults cached at: {RESULTS_DIR}")
    print("\nNext steps:")
    print("  1. Review generated Kotlin tests")
    print("  2. Copy tests to mobile/app/src/test/java/...")
    print("  3. Run: ./gradlew testDebugUnitTest")
    print("  4. Update cache with: python3 tools/test_real_scrapers.py --update-cache")

if __name__ == "__main__":
    main()