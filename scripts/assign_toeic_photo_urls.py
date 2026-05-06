from __future__ import annotations

import json
import re
import time
import urllib.parse
import urllib.request
from pathlib import Path
from urllib.error import HTTPError, URLError


ROOT = Path(__file__).resolve().parents[1]
PROMPT_BANK_PATH = ROOT / "server" / "dictionaries" / "toeic_writing_prompts.json"
COMMONS_API = "https://commons.wikimedia.org/w/api.php"


SCENE_BUCKETS = {
    "beginner": [
        {
            "title_prefix": "Cafe Counter Scene",
            "queries": [
                "outdoor cafe seating people",
                "cafe counter people",
                "coffee shop customer",
            ],
        },
        {
            "title_prefix": "Bookstore Browsing",
            "queries": [
                "bookstore customer books shelves",
                "bookshop people books",
                "bookshelves customer store",
            ],
        },
        {
            "title_prefix": "Park Bench Break",
            "queries": [
                "city park bench people",
                "people park bench",
                "bench in park person",
            ],
        },
        {
            "title_prefix": "Bus Stop Wait",
            "queries": [
                "bus stop waiting people",
                "people waiting bus stop",
                "bus shelter passengers",
            ],
        },
        {
            "title_prefix": "Grocery Checkout",
            "queries": [
                "supermarket checkout customer",
                "grocery store counter customer",
                "cashier customer supermarket",
            ],
        },
        {
            "title_prefix": "Classroom Question",
            "queries": [
                "classroom student desk",
                "students classroom desk",
                "classroom people studying",
            ],
        },
        {
            "title_prefix": "Flower Shop Visit",
            "queries": [
                "flower shop customer",
                "florist flowers customer",
                "flower market people",
            ],
        },
        {
            "title_prefix": "Library Reading Table",
            "queries": [
                "library reading table",
                "people reading library",
                "study table books person",
            ],
        },
        {
            "title_prefix": "Station Platform",
            "queries": [
                "train station platform traveler",
                "station platform passenger luggage",
                "railway platform traveler",
            ],
        },
        {
            "title_prefix": "Street Crossing Scene",
            "queries": [
                "crosswalk pedestrian city",
                "pedestrian crossing street city",
                "people crosswalk road",
            ],
        },
    ],
    "intermediate": [
        {
            "title_prefix": "Office Team Meeting",
            "queries": [
                "office meeting team table",
                "coworkers meeting office",
                "conference table team laptop",
            ],
        },
        {
            "title_prefix": "Customer Service Desk",
            "queries": [
                "reception desk customer staff",
                "service desk customer staff",
                "help desk receptionist client",
                "reception desk people",
                "information desk staff",
                "front desk customer",
            ],
        },
        {
            "title_prefix": "Shipment Preparation",
            "queries": [
                "warehouse workers boxes",
                "packing boxes workers warehouse",
                "logistics boxes people",
            ],
        },
        {
            "title_prefix": "Hotel Check-in Desk",
            "queries": [
                "hotel reception check in",
                "hotel front desk guest",
                "hotel lobby reception luggage",
            ],
        },
        {
            "title_prefix": "Clinic Reception Area",
            "queries": [
                "clinic reception waiting room",
                "medical waiting room reception",
                "clinic front desk patient",
            ],
        },
        {
            "title_prefix": "Airport Check-in",
            "queries": [
                "airport check in counter",
                "airport check in luggage",
                "traveler airport counter",
            ],
        },
        {
            "title_prefix": "Project Review Table",
            "queries": [
                "office project discussion laptop",
                "project review office table",
                "team reviewing documents office",
            ],
        },
        {
            "title_prefix": "Conference Booth Visit",
            "queries": [
                "conference booth staff visitor",
                "trade show booth visitor",
                "event booth staff people",
            ],
        },
        {
            "title_prefix": "Store Restocking",
            "queries": [
                "stock room inventory worker",
                "store room boxes worker",
                "restocking shelves worker",
                "warehouse shelves boxes worker",
                "storage room boxes",
                "retail shelf worker",
            ],
        },
        {
            "title_prefix": "Repair Counter",
            "queries": [
                "service desk customer assistance",
                "repair counter customer service",
                "customer support counter",
                "electronics service desk",
                "help desk counter person",
                "customer assistance desk people",
                "front counter staff customer",
            ],
        },
    ],
    "advanced": [
        {
            "title_prefix": "Flight Delay Discussion",
            "queries": [
                "airport terminal waiting traveler",
                "airport passengers waiting luggage",
                "airport delay traveler suitcase",
            ],
        },
        {
            "title_prefix": "Hotel Booking Problem",
            "queries": [
                "hotel front desk guest suitcase",
                "hotel reception guest luggage",
                "front desk traveler problem",
            ],
        },
        {
            "title_prefix": "Deadline Review Meeting",
            "queries": [
                "boardroom meeting documents",
                "meeting table documents laptop",
                "urgent office meeting team",
            ],
        },
        {
            "title_prefix": "Delivery Problem Review",
            "queries": [
                "warehouse delivery logistics boxes",
                "workers boxes logistics warehouse",
                "delivery boxes review warehouse",
            ],
        },
        {
            "title_prefix": "Event Registration Queue",
            "queries": [
                "conference registration queue",
                "event check in queue",
                "registration desk conference people",
            ],
        },
        {
            "title_prefix": "Restaurant Complaint",
            "queries": [
                "restaurant service counter customer",
                "restaurant customer counter complaint",
                "food counter employee customer",
            ],
        },
        {
            "title_prefix": "Store Return Request",
            "queries": [
                "store return counter customer",
                "returns desk customer store",
                "retail counter receipt customer",
            ],
        },
        {
            "title_prefix": "Travel Information Desk",
            "queries": [
                "airport information desk",
                "travel information counter airport",
                "airport help desk travelers",
            ],
        },
        {
            "title_prefix": "Project Strategy Session",
            "queries": [
                "office strategy presentation team",
                "project strategy discussion team",
                "office planning session people",
            ],
        },
        {
            "title_prefix": "Hospital Coordination Desk",
            "queries": [
                "hospital reception waiting area",
                "hospital front desk waiting room",
                "clinic waiting area desk",
            ],
        },
    ],
}


LEVEL_FALLBACK_QUERIES = {
    "beginner": [
        "people shop customer table",
        "people waiting public place",
        "person reading books room",
    ],
    "intermediate": [
        "office people desk customer staff",
        "workers boxes service counter",
        "reception meeting people indoor",
    ],
    "advanced": [
        "business travelers desk discussion",
        "conference logistics people counter",
        "customer employee formal indoor",
    ],
}


def _fetch_bytes(url: str) -> bytes:
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": "Mozilla/5.0",
            "Accept": "application/json,*/*",
        },
    )
    delay = 1.0
    for attempt in range(6):
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                payload = response.read()
                time.sleep(0.2)
                return payload
        except HTTPError as error:
            if error.code not in {429, 500, 502, 503, 504} or attempt == 5:
                raise
        except URLError:
            if attempt == 5:
                raise
        time.sleep(delay)
        delay *= 2
    raise RuntimeError(f"Failed to fetch URL after retries: {url}")


def _fetch_json(url: str) -> dict:
    return json.loads(_fetch_bytes(url).decode("utf-8"))


def _normalize_title_prefix(title: str) -> str:
    return re.sub(r"\s+\d+$", "", title).strip()


def _search_commons(query: str, page: int) -> list[dict]:
    params = {
        "action": "query",
        "format": "json",
        "generator": "search",
        "gsrnamespace": 6,
        "gsrsearch": query,
        "gsrlimit": 25,
        "page": page,
        "prop": "imageinfo",
        "iiprop": "url|size",
        "iiurlwidth": 1600,
    }
    url = f"{COMMONS_API}?{urllib.parse.urlencode(params)}"
    payload = _fetch_json(url)
    return list(payload.get("query", {}).get("pages", {}).values())


def _pick_bucket_urls(
    queries: list[str],
    *,
    target_count: int = 5,
    fallback_queries: list[str] | None = None,
) -> list[str]:
    picked: list[str] = []
    seen_urls: set[str] = set()
    seen_titles: set[str] = set()

    all_queries = list(queries)
    if fallback_queries:
        all_queries.extend(fallback_queries)

    for query in all_queries:
        for page in range(1, 5):
            for item in _search_commons(query, page):
                title = str(item.get("title") or "")
                title_lower = title.lower()
                if title.lower().endswith((".png", ".svg", ".gif")):
                    continue
                if any(
                    token in title_lower
                    for token in (
                        ".pdf",
                        "thumbnail.pdf",
                        ".webm",
                        "ia_",
                        "ia-",
                        "page1-",
                        "page2-",
                        "page3-",
                        "page4-",
                    )
                ):
                    continue
                imageinfo = item.get("imageinfo") or []
                if not imageinfo:
                    continue
                image_url = imageinfo[0].get("thumburl") or imageinfo[0].get("url")
                if not isinstance(image_url, str) or not image_url.startswith("http"):
                    continue
                image_url_lower = image_url.lower()
                if any(token in image_url_lower for token in (".pdf", ".webm", "thumbnail.pdf")):
                    continue

                width = int(imageinfo[0].get("thumbwidth") or imageinfo[0].get("width") or 0)
                height = int(imageinfo[0].get("thumbheight") or imageinfo[0].get("height") or 0)
                if width < 600 or height < 400:
                    continue

                if image_url in seen_urls or title in seen_titles:
                    continue

                seen_urls.add(image_url)
                seen_titles.add(title)
                picked.append(image_url)
                if len(picked) == target_count:
                    return picked

    raise RuntimeError(
        f"Only found {len(picked)} usable images for queries: {all_queries}",
    )


def main() -> None:
    prompt_bank = json.loads(PROMPT_BANK_PATH.read_text(encoding="utf-8"))
    updated_buckets = 0
    skipped_buckets: list[str] = []

    for level, buckets in SCENE_BUCKETS.items():
        picture_prompts = [
            prompt
            for prompt in prompt_bank
            if prompt.get("task_type") == "picture" and prompt.get("level") == level
        ]
        picture_prompts.sort(key=lambda item: str(item["prompt_id"]))

        prompts_by_bucket: dict[str, list[dict]] = {}
        for prompt in picture_prompts:
            bucket_key = _normalize_title_prefix(str(prompt["title"]))
            prompts_by_bucket.setdefault(bucket_key, []).append(prompt)

        for bucket in buckets:
            title_prefix = bucket["title_prefix"]
            prompts = prompts_by_bucket.get(title_prefix)
            if not prompts:
                raise RuntimeError(f"No prompts found for bucket {level}/{title_prefix}")

            try:
                urls = _pick_bucket_urls(
                    bucket["queries"],
                    target_count=len(prompts),
                    fallback_queries=LEVEL_FALLBACK_QUERIES[level],
                )
            except Exception:
                skipped_buckets.append(f"{level}/{title_prefix}")
                continue
            prompts.sort(key=lambda item: str(item["prompt_id"]))
            for index, (prompt, url) in enumerate(zip(prompts, urls), start=1):
                prompt["title"] = f"{title_prefix} {index}"
                prompt["image_asset"] = url
            updated_buckets += 1
            PROMPT_BANK_PATH.write_text(
                json.dumps(prompt_bank, ensure_ascii=False, indent=2),
                encoding="utf-8",
            )

    PROMPT_BANK_PATH.write_text(
        json.dumps(prompt_bank, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(
        f"Assigned scene-matched photo URLs for {updated_buckets} buckets; "
        f"skipped {len(skipped_buckets)} buckets",
    )
    if skipped_buckets:
        print("Skipped buckets:")
        for item in skipped_buckets:
            print(f"- {item}")


if __name__ == "__main__":
    main()
