#!/usr/bin/env python3
"""
Resolve musl runtime URL by scraping the beammachine page.

This script searches for anchor tags in HTML content that match "runtime"
and the specified architecture needle, then outputs the resolved URL.
"""

import argparse
import html as htmllib
import os
import re
import sys
from urllib.parse import urljoin


def normalize_text(text: str) -> str:
    """Normalize text by removing HTML tags, unescaping, and normalizing whitespace."""
    text = re.sub(r"<[^>]+>", " ", text)
    text = htmllib.unescape(text)
    return re.sub(r"\s+", " ", text).strip().lower()


def resolve_musl_runtime_url(html: str, home_url: str, needle_arch: str) -> str:
    """
    Find the musl runtime URL from HTML content.
    
    Args:
        html: HTML content to search
        home_url: Base URL for resolving relative URLs
        needle_arch: Architecture to search for (e.g., "x86_64", "aarch64")
    
    Returns:
        Resolved URL string
    
    Raises:
        SystemExit: Exits with code 1 if URL cannot be found
    """
    needle = needle_arch.lower()
    
    # Find all anchor tags with href attributes
    anchors = re.findall(
        r"<a\s+[^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>",
        html,
        flags=re.IGNORECASE | re.DOTALL
    )
    
    # Search for anchors matching "runtime" and the architecture needle
    for href, inner in anchors:
        href_unescaped = htmllib.unescape(href)
        haystack = (href_unescaped + " " + normalize_text(inner)).lower()
        if "runtime" in haystack and needle in haystack:
            resolved_url = urljoin(home_url, href_unescaped)
            return resolved_url
    
    # URL not found
    sys.exit(1)


def main():
    """Main entry point for the script."""
    parser = argparse.ArgumentParser(
        description="Resolve musl runtime URL from HTML content"
    )
    parser.add_argument(
        "--html",
        type=str,
        help="HTML content to search (can also be provided via HTML environment variable or stdin)"
    )
    parser.add_argument(
        "--home-url",
        type=str,
        help="Base URL for resolving relative URLs (can also be provided via HOME_URL environment variable)"
    )
    parser.add_argument(
        "--needle-arch",
        type=str,
        help="Architecture to search for (can also be provided via NEEDLE_ARCH environment variable)"
    )
    
    args = parser.parse_args()
    
    # Get HTML content from argument, environment variable, or stdin
    if args.html:
        html = args.html
    elif "HTML" in os.environ:
        html = os.environ["HTML"]
    elif not sys.stdin.isatty():
        html = sys.stdin.read()
    else:
        parser.error("HTML content must be provided via --html, HTML environment variable, or stdin")
    
    # Get HOME_URL from argument or environment variable
    home_url = args.home_url or os.environ.get("HOME_URL")
    if not home_url:
        parser.error("HOME_URL must be provided via --home-url or HOME_URL environment variable")
    
    # Get NEEDLE_ARCH from argument or environment variable
    needle_arch = args.needle_arch or os.environ.get("NEEDLE_ARCH")
    if not needle_arch:
        parser.error("NEEDLE_ARCH must be provided via --needle-arch or NEEDLE_ARCH environment variable")
    
    # Resolve and output the URL
    try:
        url = resolve_musl_runtime_url(html, home_url, needle_arch)
        print(url)
        sys.exit(0)
    except SystemExit:
        raise
    except Exception as e:
        print(f"Error resolving musl runtime URL: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
