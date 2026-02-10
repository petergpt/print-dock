#!/usr/bin/env python3
"""Build a same-day news digest from Google News RSS and craft an image prompt."""

from __future__ import annotations

import argparse
import collections
import datetime as dt
import email.utils
import json
import re
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any

FEEDS: dict[str, str] = {
    "top": "https://news.google.com/rss?hl=en-US&gl=US&ceid=US:en",
    "world": "https://news.google.com/rss/headlines/section/topic/WORLD?hl=en-US&gl=US&ceid=US:en",
    "business": "https://news.google.com/rss/headlines/section/topic/BUSINESS?hl=en-US&gl=US&ceid=US:en",
    "technology": "https://news.google.com/rss/headlines/section/topic/TECHNOLOGY?hl=en-US&gl=US&ceid=US:en",
    "science": "https://news.google.com/rss/headlines/section/topic/SCIENCE?hl=en-US&gl=US&ceid=US:en",
    "entertainment": "https://news.google.com/rss/headlines/section/topic/ENTERTAINMENT?hl=en-US&gl=US&ceid=US:en",
    "sports": "https://news.google.com/rss/headlines/section/topic/SPORTS?hl=en-US&gl=US&ceid=US:en",
}

THEME_KEYWORDS: dict[str, list[str]] = {
    "geopolitics": [
        "war", "conflict", "border", "sanction", "summit", "treaty", "diplom", "election", "government", "minister",
    ],
    "economy": [
        "market", "stocks", "inflation", "jobs", "economy", "trade", "tariff", "rate", "earnings", "gdp", "recession",
    ],
    "technology": [
        "ai", "artificial intelligence", "chip", "software", "cyber", "robot", "startup", "app", "platform", "data",
    ],
    "science": [
        "science", "research", "study", "discovery", "space", "nasa", "astronomy", "biology", "physics", "medicine",
    ],
    "climate": [
        "climate", "storm", "flood", "fire", "wildfire", "heat", "hurricane", "weather", "emissions", "drought",
    ],
    "health": [
        "health", "virus", "disease", "hospital", "vaccine", "medical", "drug", "cdc", "who", "outbreak",
    ],
    "culture-sports": [
        "film", "music", "festival", "art", "sports", "olympic", "cup", "league", "award", "celebrity",
    ],
}

THEME_LABELS: dict[str, str] = {
    "geopolitics": "global politics",
    "economy": "economic pressure",
    "technology": "technology acceleration",
    "science": "scientific discovery",
    "climate": "climate and extreme weather",
    "health": "public health",
    "culture-sports": "culture and sports",
}

THEME_MOTIFS: dict[str, list[str]] = {
    "science": ["orbits", "observatories", "balloons", "lab glass", "starlight"],
    "technology": ["circuits", "robots", "holograms", "launchpads", "neon interfaces"],
    "culture-sports": ["stadium lights", "confetti", "music waves", "spotlights", "crowds"],
    "economy": ["city skylines", "market boards", "cargo routes", "bridges", "sunrise offices"],
    "geopolitics": ["globes", "maps", "meeting tables", "diplomatic halls", "city landmarks"],
    "climate": ["wind turbines", "oceans", "green canopies", "sunbeams", "rainclouds"],
    "health": ["care teams", "wellness icons", "clinical labs", "healing hands", "clean interiors"],
}

FUN_BOOST_KEYWORDS = {
    "discovery",
    "breakthrough",
    "innovation",
    "festival",
    "premiere",
    "award",
    "space",
    "nasa",
    "art",
    "music",
    "film",
    "robot",
    "science",
    "wildlife",
    "design",
    "launch",
    "record",
    "championship",
    "victory",
}

HEAVY_DOWNRANK_KEYWORDS = {
    "killed",
    "killing",
    "dead",
    "death",
    "dies",
    "murder",
    "massacre",
    "shooting",
    "airstrike",
    "missile",
    "bomb",
    "war",
    "hostage",
    "earthquake",
    "flood",
    "wildfire",
    "hurricane",
    "disaster",
    "investigation",
    "allegedly",
    "lawsuit",
    "scandal",
    "epstein",
    "mishap",
    "crime",
    "leak",
    "curse",
}

FUN_FEED_BOOST = {
    "science": 3,
    "technology": 3,
    "entertainment": 4,
    "sports": 4,
    "business": 1,
}

STOPWORDS = {
    "the", "and", "for", "with", "from", "that", "this", "after", "over", "into", "about", "amid", "under",
    "more", "than", "new", "its", "their", "his", "her", "are", "was", "were", "will", "would", "can",
    "today", "says", "say", "live", "update", "latest", "news", "as", "at", "of", "to", "in", "on", "by",
}

MOTIF_EXCLUDE = {
    "why",
    "what",
    "when",
    "where",
    "this",
    "that",
    "these",
    "those",
    "deja",
    "cant",
    "won't",
    "dont",
    "into",
    "without",
    "after",
    "before",
    "amid",
    "says",
    "said",
}


def fetch_xml(url: str) -> ET.Element:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "Codex-Surprise-Print/1.0 (news digest)",
            "Accept": "application/rss+xml, application/xml;q=0.9, */*;q=0.8",
        },
    )
    with urllib.request.urlopen(req, timeout=20) as resp:
        data = resp.read()
    return ET.fromstring(data)


def parse_title(raw: str) -> tuple[str, str]:
    raw = re.sub(r"\s+", " ", raw).strip()
    if " - " not in raw:
        return raw, "Unknown"
    title, source = raw.rsplit(" - ", 1)
    title = title.strip() or raw
    source = source.strip() or "Unknown"
    return title, source


def parse_date(raw: str) -> dt.datetime:
    if not raw:
        return dt.datetime.now(dt.timezone.utc)
    parsed = email.utils.parsedate_to_datetime(raw)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed.astimezone(dt.timezone.utc)


def normalize_key(title: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", title.lower()).strip()


def score_item_for_fun(item: dict[str, Any]) -> int:
    title = item["title"].lower()
    score = FUN_FEED_BOOST.get(item["feed"], 0)

    for kw in FUN_BOOST_KEYWORDS:
        if kw in title:
            score += 2

    for kw in HEAVY_DOWNRANK_KEYWORDS:
        if kw in title:
            score -= 6

    return score


def fetch_items() -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    now = dt.datetime.now(dt.timezone.utc)
    cutoff = now - dt.timedelta(hours=36)

    for feed_name, url in FEEDS.items():
        root = fetch_xml(url)
        for node in root.findall("./channel/item"):
            raw_title = (node.findtext("title") or "").strip()
            if not raw_title:
                continue
            title, source = parse_title(raw_title)
            link = (node.findtext("link") or "").strip()
            published = parse_date((node.findtext("pubDate") or "").strip())
            if published < cutoff:
                continue
            items.append(
                {
                    "title": title,
                    "source": source,
                    "link": link,
                    "published_utc": published.isoformat(),
                    "published_ts": published.timestamp(),
                    "feed": feed_name,
                }
            )

    return items


def dedupe_and_select(items: list[dict[str, Any]], max_items: int) -> list[dict[str, Any]]:
    items_sorted = sorted(items, key=lambda x: x["published_ts"], reverse=True)

    deduped: list[dict[str, Any]] = []
    seen: set[str] = set()
    for item in items_sorted:
        key = normalize_key(item["title"])
        if not key or key in seen:
            continue
        seen.add(key)
        deduped.append(item)

    scored = [
        {
            **item,
            "fun_score": score_item_for_fun(item),
        }
        for item in deduped
    ]
    ranked = sorted(scored, key=lambda x: (x["fun_score"], x["published_ts"]), reverse=True)

    selected: list[dict[str, Any]] = []
    per_source: collections.Counter[str] = collections.Counter()

    for item in ranked:
        if len(selected) >= max_items:
            break
        if item["fun_score"] < -5:
            continue
        source = item["source"]
        if per_source[source] >= 2:
            continue
        selected.append(item)
        per_source[source] += 1

    if len(selected) < max_items:
        for item in ranked:
            if len(selected) >= max_items:
                break
            if item in selected:
                continue
            selected.append(item)

    return selected


def detect_themes(headlines: list[str]) -> list[str]:
    scores: collections.Counter[str] = collections.Counter()
    text_blobs = [h.lower() for h in headlines]

    for blob in text_blobs:
        for theme, keywords in THEME_KEYWORDS.items():
            for kw in keywords:
                if kw in blob:
                    scores[theme] += 1
                    break

    ranked = [theme for theme, _ in scores.most_common()]
    if not ranked:
        ranked = ["culture-sports", "technology", "economy"]

    while len(ranked) < 3:
        for fallback in ["culture-sports", "technology", "economy", "science", "health", "geopolitics", "climate"]:
            if fallback not in ranked:
                ranked.append(fallback)
            if len(ranked) >= 3:
                break

    return ranked[:3]


def top_terms(headlines: list[str], limit: int = 7) -> list[str]:
    counter: collections.Counter[str] = collections.Counter()

    for headline in headlines:
        for token in re.findall(r"[A-Za-z][A-Za-z0-9'-]{2,}", headline.lower()):
            if token in STOPWORDS:
                continue
            if token in MOTIF_EXCLUDE:
                continue
            if token.isdigit():
                continue
            counter[token] += 1

    weighted: list[str] = []
    for term, count in counter.most_common():
        if count >= 2:
            weighted.append(term)
        if len(weighted) >= limit:
            break

    return weighted


def compose_motifs(themes: list[str], extracted: list[str], limit: int = 7) -> list[str]:
    motifs: list[str] = []

    for term in extracted:
        cleaned = term.replace("-", " ").strip()
        if cleaned and cleaned not in motifs:
            motifs.append(cleaned)
        if len(motifs) >= limit:
            return motifs

    for theme in themes:
        for motif in THEME_MOTIFS.get(theme, []):
            if motif in motifs:
                continue
            motifs.append(motif)
            if len(motifs) >= limit:
                return motifs

    return motifs[:limit]


def build_prompt(themes: list[str], motifs: list[str]) -> str:
    theme_labels = [THEME_LABELS.get(t, t) for t in themes]
    motifs_text = ", ".join(motifs) if motifs else "celebration, discovery, motion, confetti, bright city lights"
    themes_text = ", ".join(theme_labels)

    return (
        "Create a vertical editorial illustration that captures today's U.S. news atmosphere across multiple stories with an uplifting, playful tone. "
        f"Primary themes: {themes_text}. "
        f"Symbolic motifs: {motifs_text}. "
        "Visual direction: whimsical magazine-cover collage, bright optimistic palette, expressive shapes, dynamic but coherent composition, "
        "storybook energy with polished editorial finish. Keep politically neutral in tone and avoid any graphic, violent, or disaster imagery. "
        "Do not include any words, letters, numbers, logos, or watermarks."
    )


def build_payload(selected: list[dict[str, Any]]) -> dict[str, Any]:
    headlines = [item["title"] for item in selected]
    themes = detect_themes(headlines)
    extracted_motifs = top_terms(headlines)
    motifs = compose_motifs(themes, extracted_motifs)

    theme_sentence = (
        f"Today's headlines converge around {THEME_LABELS.get(themes[0], themes[0])}, "
        f"{THEME_LABELS.get(themes[1], themes[1])}, and {THEME_LABELS.get(themes[2], themes[2])}."
    )

    return {
        "headline": "Bright news pulse: Today",
        "fact": theme_sentence,
        "theme_summary": theme_sentence,
        "source_title": "Google News RSS (multiple publishers)",
        "source_url": FEEDS["top"],
        "prompt": build_prompt(themes, motifs),
        "tone": "uplifting-playful",
        "themes": themes,
        "motifs": motifs,
        "headline_count": len(selected),
        "headlines": [
            {
                "title": item["title"],
                "source": item["source"],
                "published_utc": item["published_utc"],
                "link": item["link"],
                "feed": item["feed"],
            }
            for item in selected
        ],
        "mode": "news-digest",
        "date": dt.datetime.now(dt.timezone.utc).date().isoformat(),
        "as_of_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Fetch daily news digest for surprise-print")
    parser.add_argument("--max-items", type=int, default=12)
    parser.add_argument("--out")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    max_items = max(5, min(args.max_items, 25))

    try:
        items = fetch_items()
    except Exception as exc:
        raise SystemExit(f"Failed to fetch RSS feeds: {exc}")

    if not items:
        raise SystemExit("No news items were fetched.")

    selected = dedupe_and_select(items, max_items=max_items)
    payload = build_payload(selected)

    output = json.dumps(payload, indent=2, ensure_ascii=False)
    if args.out:
        out_path = Path(args.out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(output + "\n", encoding="utf-8")

    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
