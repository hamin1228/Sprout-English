from __future__ import annotations

import json
import time
import urllib.parse
import urllib.request
from pathlib import Path
from urllib.error import HTTPError, URLError


ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = ROOT / "assets" / "toeic_writing_images"
COMMONS_API = "https://commons.wikimedia.org/w/api.php"


QUERY_GROUPS = {
    "beginner": [
        "outdoor cafe seating people",
        "bookstore customer books shelves",
        "city park bench people",
        "bus stop waiting people",
        "supermarket checkout customer",
        "classroom student desk",
        "flower shop customer",
        "library reading table",
        "train station platform traveler",
        "crosswalk pedestrian city",
    ],
    "intermediate": [
        "office meeting team table",
        "reception desk customer staff",
        "warehouse workers boxes",
        "hotel reception check in",
        "clinic reception waiting room",
        "airport check in counter",
        "office project discussion laptop",
        "conference booth staff visitor",
        "stock room inventory worker",
        "service desk customer assistance",
    ],
    "advanced": [
        "airport terminal waiting traveler",
        "hotel front desk guest suitcase",
        "boardroom meeting documents",
        "warehouse delivery logistics boxes",
        "conference registration queue",
        "restaurant service counter customer",
        "store return counter customer",
        "airport information desk",
        "office strategy presentation team",
        "hospital reception waiting area",
    ],
}


def _fetch_bytes(url: str) -> bytes:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "Mozilla/5.0",
            "Accept": "*/*",
        },
    )
    delay = 1.0
    for attempt in range(6):
        try:
            with urllib.request.urlopen(req, timeout=30) as response:
                payload = response.read()
                time.sleep(0.4)
                return payload
        except HTTPError as error:
            if error.code not in {429, 503, 504} or attempt == 5:
                raise
        except URLError:
            if attempt == 5:
                raise
        time.sleep(delay)
        delay *= 2
    raise RuntimeError(f"Failed to fetch URL after retries: {url}")


def _search_commons(query: str, limit: int = 20) -> list[tuple[str, str]]:
    params = {
        "action": "query",
        "format": "json",
        "generator": "search",
        "gsrnamespace": 6,
        "gsrlimit": limit,
        "gsrsearch": query,
        "prop": "imageinfo",
        "iiprop": "url",
        "iiurlwidth": 1400,
    }
    url = f"{COMMONS_API}?{urllib.parse.urlencode(params)}"
    payload = json.loads(_fetch_bytes(url).decode("utf-8"))
    pages = payload.get("query", {}).get("pages", {})
    results: list[tuple[str, str]] = []
    for page in pages.values():
        title = str(page.get("title", ""))
        if not title.lower().endswith((".jpg", ".jpeg")):
            continue
        imageinfo = page.get("imageinfo") or []
        if not imageinfo:
            continue
        image_url = imageinfo[0].get("thumburl") or imageinfo[0].get("url")
        if isinstance(image_url, str) and image_url.startswith("http"):
            results.append((title, image_url))
    return results


def _download_unique_images(level: str) -> None:
    level_dir = ASSET_ROOT / level
    level_dir.mkdir(parents=True, exist_ok=True)
    used_titles: set[str] = set()
    used_urls: set[str] = set()
    downloaded = 0

    for query in QUERY_GROUPS[level]:
        results = _search_commons(query, limit=30)
        for title, url in results:
            if title in used_titles or url in used_urls:
                continue
            destination = level_dir / f"scene_{downloaded + 1:02d}.jpg"
            destination.write_bytes(_fetch_bytes(url))
            used_titles.add(title)
            used_urls.add(url)
            downloaded += 1
            print(f"downloaded {destination.relative_to(ROOT)} from {title}")
            if downloaded == 50:
                return

    raise RuntimeError(f"Only downloaded {downloaded} unique images for {level}")


def main() -> None:
    for level in ("beginner", "intermediate", "advanced"):
        _download_unique_images(level)


if __name__ == "__main__":
    main()
