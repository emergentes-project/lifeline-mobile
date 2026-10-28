from __future__ import annotations

import argparse
import json
import re
import unicodedata
from collections import Counter, defaultdict
from pathlib import Path

from generate_medical_bases import ROOT, OUTPUT, SOURCE, build


PACKAGE_DIR = ROOT / "assets/medical_bases/packages/post_sismo_1_0_0"
EMERGENCY_NUMBER = re.compile(r"\b(?:105|106|116|117|911|999)\b")
WORD = re.compile(r"[a-z0-9]+")
STOP_WORDS = frozenset(
    "a al ante con de del el en entre es esta este hay la las lo los o para por que se si sin su sus un una y".split()
)


def terms(value: str) -> list[str]:
    folded = unicodedata.normalize("NFKD", value.lower())
    ascii_text = "".join(char for char in folded if not unicodedata.combining(char))
    return [word for word in WORD.findall(ascii_text) if len(word) >= 3 and word not in STOP_WORDS]


def institution(title: str) -> str:
    return title.split(",", 1)[0].strip()


def make_package(cards: dict) -> dict[str, dict | list]:
    source_by_url = {}
    sources = []
    for card in cards["cards"]:
        for source in card["sources"]:
            if source["url"] in source_by_url:
                continue
            source_id = f"source_{len(sources) + 1:03d}"
            source_by_url[source["url"]] = source_id
            sources.append(
                {
                    "id": source_id,
                    "institution": institution(source["title"]),
                    "title": source["title"],
                    "url": source["url"],
                    "edition": None,
                }
            )

    chunks = []
    for card in cards["cards"]:
        source_ids = [source_by_url[source["url"]] for source in card["sources"]]
        for section, field in (("measures", "measures"), ("medical_indications", "medical_indications")):
            chunks.append(
                {
                    "id": f"{card['id']}_{section}_basic",
                    "card_id": card["id"],
                    "card_number": card["number"],
                    "card_title": card["title"],
                    "section": section,
                    "kind": "basic",
                    "ordinal": 0,
                    "text": card[field]["basic"],
                    "source_ids": source_ids,
                }
            )
            for number, rule in enumerate(card[field]["conditional"], start=1):
                chunks.append(
                    {
                        "id": f"{card['id']}_{section}_conditional_{number:02d}",
                        "card_id": card["id"],
                        "card_number": card["number"],
                        "card_title": card["title"],
                        "section": section,
                        "kind": "conditional",
                        "ordinal": number,
                        "text": rule,
                        "source_ids": source_ids,
                    }
                )
        chunks.append(
            {
                "id": f"{card['id']}_professional_help",
                "card_id": card["id"],
                "card_number": card["number"],
                "card_title": card["title"],
                "section": "professional_help",
                "kind": "basic",
                "ordinal": 0,
                "text": card["professional_help"],
                "source_ids": source_ids,
            }
        )

    postings = defaultdict(list)
    lengths = []
    for chunk_index, chunk in enumerate(chunks):
        frequencies = Counter(terms(chunk["card_title"]) * 3 + terms(chunk["text"]))
        lengths.append(sum(frequencies.values()))
        for term, frequency in frequencies.items():
            postings[term].append([chunk_index, frequency])

    manifest = {
        "schema_version": 1,
        "package_id": cards["package_id"],
        "version": cards["version"],
        "locale": cards["locale"],
        "card_count": len(cards["cards"]),
        "source_count": len(sources),
        "chunk_count": len(chunks),
        "response_sections": cards["response_sections"],
        "common_safety_rule": cards["common_safety_rule"],
        "source_scope": "card",
        "source_markdown": "assets/medical_bases/fichas_post_sismo_v1.md",
        "source_json": "assets/medical_bases/fichas_post_sismo_v1.json",
        "search_index": "bm25_lexical_v1",
    }
    index = {
        "schema_version": 1,
        "package_id": cards["package_id"],
        "version": cards["version"],
        "normalization": "lowercase_unicode_nfkd_ascii_words_min3_stopwords_v1",
        "stop_words": sorted(STOP_WORDS),
        "document_lengths": lengths,
        "average_document_length": sum(lengths) / len(lengths),
        "postings": {term: postings[term] for term in sorted(postings)},
    }
    return {
        "manifest.json": manifest,
        "sources.json": sources,
        "chunks.json": chunks,
        "index.json": index,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    markdown = SOURCE.read_text(encoding="utf-8")
    approved_cards = build(markdown)
    expected_cards = json.dumps(approved_cards, ensure_ascii=False, indent=2) + "\n"
    if OUTPUT.read_text(encoding="utf-8") != expected_cards:
        raise SystemExit("The approved JSON is not synchronized with the Markdown")
    package = make_package(approved_cards)
    for name, data in package.items():
        content = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
        if name != "index.json" and EMERGENCY_NUMBER.search(content):
            raise SystemExit(f"An emergency phone number was found in {name}")
        target = PACKAGE_DIR / name
        if args.check:
            if not target.exists() or target.read_text(encoding="utf-8") != content:
                raise SystemExit(f"Package file is out of date: {name}")
        else:
            PACKAGE_DIR.mkdir(parents=True, exist_ok=True)
            target.write_text(content, encoding="utf-8")
    verb = "Verified" if args.check else "Generated"
    print(f"{verb} package {approved_cards['version']}: {len(approved_cards['cards'])} cards, "
          f"{len(package['sources.json'])} sources, {len(package['chunks.json'])} chunks")


if __name__ == "__main__":
    main()
