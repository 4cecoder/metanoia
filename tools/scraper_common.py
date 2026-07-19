"""Shared HTTP-fetch helper for the BibleHub scrapers
(interlinear_scraper.py, lexicon_scraper.py).

Provides retry-with-backoff for *transient* failures only: timeouts,
connection errors, and 5xx responses. A 4xx response is treated as a real
"this page doesn't exist" signal (e.g. many deuterocanonical / Ethiopian-canon
books simply have no BibleHub page) and is returned immediately without
retrying -- retrying it would just waste time.
"""

import time

import requests

# Server-side errors worth retrying. 4xx is deliberately excluded.
_TRANSIENT_STATUS_CODES = frozenset({500, 502, 503, 504})


def fetch_with_retry(url, *, headers=None, timeout=15, attempts=3, backoff=1.0):
    """GET `url`, retrying on transient failures with exponential backoff.

    Retries (up to `attempts` tries total, sleeping `backoff`, `backoff*2`,
    `backoff*4`, ... between them) on:
      - requests.Timeout / requests.ConnectionError
      - HTTP 5xx responses

    Does NOT retry on:
      - HTTP 4xx responses (returned as-is on first attempt; caller decides
        what to do, e.g. raise_for_status() or treat as "not found")
      - other requests.RequestException subclasses (e.g. TooManyRedirects,
        InvalidURL) -- these indicate a request that will never succeed

    Returns the `requests.Response` from the first non-transient outcome.
    Raises the last transient exception if every attempt fails with one.
    """
    delay = backoff
    last_exc = None

    for attempt in range(1, attempts + 1):
        try:
            response = requests.get(url, headers=headers, timeout=timeout)
        except (requests.Timeout, requests.ConnectionError) as exc:
            last_exc = exc
            if attempt == attempts:
                raise
            time.sleep(delay)
            delay *= 2
            continue

        if response.status_code in _TRANSIENT_STATUS_CODES:
            if attempt == attempts:
                return response
            time.sleep(delay)
            delay *= 2
            continue

        return response

    # Unreachable in practice (loop always returns or raises above), but keep
    # the function total in case attempts <= 0 is ever passed.
    if last_exc is not None:
        raise last_exc
    raise RuntimeError("fetch_with_retry: no attempts made")
