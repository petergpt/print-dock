#!/usr/bin/env python3
"""Fetch a surprising fact from Wikipedia sources and emit a structured JSON payload."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import random
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

ON_THIS_DAY_URL = "https://en.wikipedia.org/api/rest_v1/feed/onthisday/events/{month}/{day}"
RANDOM_SUMMARY_URL = "https://en.wikipedia.org/api/rest_v1/page/random/summary"

FALLBACK_FACTS = [
    {
        "headline": "Printing on tiny paper changed journalism",
        "fact": "In 1702, The Daily Courant became England's first daily newspaper.",
        "source_title": "The Daily Courant",
        "source_url": "https://en.wikipedia.org/wiki/The_Daily_Courant",
        "prompt": "Vintage newsroom scene with a hand-fed press printing the first daily newspaper, warm morning light, intricate paper texture, cinematic composition, no text.",
    },
    {
        "headline": "A camera once weighed as much as furniture",
        "fact": "Early studio cameras in the 1800s were large wooden systems that required long exposures.",
        "source_title": "Large format camera",
        "source_url": "https://en.wikipedia.org/wiki/Large_format",
        "prompt": "Moody 19th-century photo studio with an oversized wooden camera on tripod, dust in sunbeams, film-era textures, no text.",
    },
    {
        "headline": "Radio once carried weather from ships in Morse",
        "fact": "By the early 1900s, ships relayed weather observations using wireless telegraphy.",
        "source_title": "Wireless telegraphy",
        "source_url": "https://en.wikipedia.org/wiki/Wireless_telegraphy",
        "prompt": "Atmospheric ocean vessel radio room with Morse transmission equipment, brass instruments, stormy horizon outside, no text.",
    },
]


def fetch_json(url: str) -> dict[str, Any]:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "Codex-Surprise-Print/1.0 (research + art workflow)",
            "Accept": "application/json",
        },
    )
    with urllib.request.urlopen(req, timeout=20) as resp:
        return json.loads(resp.read().decode("utf-8"))


def clean_text(value: str) -> str:
    value = re.sub(r"\s+", " ", value).strip()
    return value


def build_prompt_from_fact(fact: str) -> str:
    return (
        "Create a visually rich vertical illustration inspired by this real-world fact: "
        f"{fact} "
        "Style: cinematic editorial illustration, detailed environment, tactile textures, balanced composition, "
        "dramatic but tasteful lighting. Do not include any words, letters, logos, or watermarks."
    )


def pick_on_this_day(month: int, day: int, seed: int | None) -> dict[str, Any]:
    payload = fetch_json(ON_THIS_DAY_URL.format(month=month, day=day))
    events: list[dict[str, Any]] = payload.get("events", [])
    candidates: list[dict[str, Any]] = []

    for event in events:
        text = clean_text(str(event.get("text", "")))
        if len(text) < 40:
            continue
        pages = event.get("pages") or []
        if not pages:
            continue
        page = pages[0]
        title = clean_text(str(page.get("normalizedtitle") or page.get("title") or "Wikipedia"))
        source_url = ""
        content_urls = page.get("content_urls") or {}
        desktop = content_urls.get("desktop") if isinstance(content_urls, dict) else None
        if isinstance(desktop, dict):
            source_url = str(desktop.get("page") or "")
        if not source_url:
            source_url = f"https://en.wikipedia.org/wiki/{title.replace(' ', '_')}"

        year = event.get("year")
        fact = f"In {year}, {text}" if year else text
        candidates.append(
            {
                "headline": f"On this day: {title}",
                "fact": fact,
                "source_title": title,
                "source_url": source_url,
                "prompt": build_prompt_from_fact(fact),
            }
        )

    if not candidates:
        raise RuntimeError("No viable on-this-day events returned")

    rng = random.Random(seed if seed is not None else month * 100 + day)
    return rng.choice(candidates)


def pick_random_summary(seed: int | None) -> dict[str, Any]:
    payload = fetch_json(RANDOM_SUMMARY_URL)
    title = clean_text(str(payload.get("title", "Wikipedia")))
    extract = clean_text(str(payload.get("extract", "")))
    if len(extract) < 40:
        raise RuntimeError("Random summary is too short")

    lines = re.split(r"(?<=[.!?])\s+", extract)
    one_liner = lines[0] if lines else extract
    fact = f"{title}: {one_liner}"

    source_url = ""
    content_urls = payload.get("content_urls") or {}
    desktop = content_urls.get("desktop") if isinstance(content_urls, dict) else None
    if isinstance(desktop, dict):
        source_url = str(desktop.get("page") or "")
    if not source_url:
        source_url = f"https://en.wikipedia.org/wiki/{title.replace(' ', '_')}"

    candidate = {
        "headline": f"Random wonder: {title}",
        "fact": fact,
        "source_title": title,
        "source_url": source_url,
        "prompt": build_prompt_from_fact(fact),
    }

    # Optional deterministic variation path if a seed is supplied.
    if seed is not None:
        rng = random.Random(seed)
        style_suffix = rng.choice(
            [
                "Use a poster-like composition with deep perspective.",
                "Use a painterly style with soft edge lighting.",
                "Use a retro-futurist aesthetic with restrained color accents.",
            ]
        )
        candidate["prompt"] = f"{candidate['prompt']} {style_suffix}"

    return candidate


def fallback(seed: int | None) -> dict[str, Any]:
    rng = random.Random(seed if seed is not None else 0)
    return rng.choice(FALLBACK_FACTS)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Fetch a surprise fact for the surprise-print skill")
    parser.add_argument("--mode", choices=["on-this-day", "random-summary"], default="on-this-day")
    parser.add_argument("--month", type=int, help="Month for on-this-day mode")
    parser.add_argument("--day", type=int, help="Day for on-this-day mode")
    parser.add_argument("--seed", type=int, help="Optional random seed")
    parser.add_argument("--out", help="Optional JSON output path")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    today = dt.date.today()
    month = args.month or today.month
    day = args.day or today.day

    try:
        if args.mode == "on-this-day":
            result = pick_on_this_day(month, day, args.seed)
            result["mode"] = "on-this-day"
            result["date"] = f"{month:02d}-{day:02d}"
        else:
            result = pick_random_summary(args.seed)
            result["mode"] = "random-summary"
            result["date"] = today.isoformat()
    except (urllib.error.URLError, TimeoutError, RuntimeError) as exc:
        result = fallback(args.seed)
        result["mode"] = "fallback"
        result["date"] = today.isoformat()
        result["warning"] = f"Research fallback used: {exc}"

    payload = json.dumps(result, indent=2, ensure_ascii=False)
    if args.out:
        out_path = Path(args.out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(payload + "\n", encoding="utf-8")

    print(payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
