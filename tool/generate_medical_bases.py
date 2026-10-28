"""Build the app's structured medical cards from the reviewed Markdown."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/medical_bases/fichas_post_sismo_v1.md"
OUTPUT = ROOT / "assets/medical_bases/fichas_post_sismo_v1.json"
CARD_HEADING = re.compile(r"(?m)^## (\d+)\. (.+)$")
SOURCE_LINK = re.compile(r"\[([^\]]+)\]\((https?://[^)]+)\)")
EMERGENCY_NUMBER = re.compile(r"\b(?:105|106|116|117|911|999)\b")


def plain(value: str) -> str:
    return re.sub(r"\*\*(.*?)\*\*", r"\1", value).strip()


def section(body: str, start: str, end: str) -> str:
    match = re.search(
        rf"(?ms)^\*\*{re.escape(start)}\*\*\s*(.*?)^\*\*{re.escape(end)}\*\*",
        body,
    )
    if not match:
        raise ValueError(f"Missing section: {start}")
    return match.group(1)


def guidance(block: str) -> dict[str, object]:
    basic = re.search(r"(?m)^\*\*Pauta básica:\*\* (.+)$", block)
    conditional = re.search(r"(?ms)^\*\*Según el caso:\*\*\s*(.+)$", block)
    if not basic or not conditional:
        raise ValueError("Each guidance section needs a basic action and conditions")
    rules = [plain(item) for item in re.findall(r"(?m)^- (.+)$", conditional.group(1))]
    if not rules:
        raise ValueError("Each guidance section needs conditional rules")
    return {"basic": plain(basic.group(1)), "conditional": rules}


def build(source: str) -> dict[str, object]:
    headings = list(CARD_HEADING.finditer(source))
    if len(headings) != 13:
        raise ValueError(f"Expected 13 cards, found {len(headings)}")

    common = re.search(r"(?m)^\*\*Regla común para el sistema:\*\* (.+)$", source)
    if not common:
        raise ValueError("Missing common safety rule")

    cards = []
    for index, heading in enumerate(headings):
        number = int(heading.group(1))
        if number != index + 1:
            raise ValueError(f"Unexpected card number: {number}")
        end = headings[index + 1].start() if index + 1 < len(headings) else len(source)
        body = source[heading.end() : end]
        help_match = re.search(
            r"(?m)^\*\*¿Es necesario pedir ayuda profesional\?\*\* (.+)$",
            body,
        )
        sources_match = re.search(r"(?m)^Fuentes: (.+)$", body)
        if not help_match or not sources_match:
            raise ValueError(f"Missing help decision or sources for card {number}")
        links = [
            {"title": title, "url": url}
            for title, url in SOURCE_LINK.findall(sources_match.group(1))
        ]
        if not links:
            raise ValueError(f"No sources for card {number}")

        cards.append(
            {
                "id": f"post_sismo_{number:02d}",
                "number": number,
                "title": heading.group(2).strip(),
                "measures": guidance(
                    section(body, "Medidas a tomar:", "Indicaciones médicas a ejecutar:")
                ),
                "medical_indications": guidance(
                    section(
                        body,
                        "Indicaciones médicas a ejecutar:",
                        "¿Es necesario pedir ayuda profesional?",
                    )
                ),
                "professional_help": plain(help_match.group(1)),
                "sources": links,
            }
        )

    package = {
        "schema_version": 1,
        "package_id": "lifeline_post_sismo",
        "version": "1.0.0",
        "locale": "es-PE",
        "response_sections": [
            "Medidas a tomar",
            "Indicaciones médicas a ejecutar",
            "¿Es necesario pedir ayuda profesional?",
        ],
        "common_safety_rule": plain(common.group(1)),
        "cards": cards,
    }
    if EMERGENCY_NUMBER.search(json.dumps(package, ensure_ascii=False)):
        raise ValueError("An emergency phone number was found in the package")
    return package


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="Verify JSON matches Markdown")
    args = parser.parse_args()
    package = build(SOURCE.read_text(encoding="utf-8"))
    content = json.dumps(package, ensure_ascii=False, indent=2) + "\n"
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text(encoding="utf-8") != content:
            raise SystemExit("JSON is not in sync with the Markdown source")
        print(f"Verified {len(package['cards'])} medical cards")
    else:
        OUTPUT.write_text(content, encoding="utf-8")
        print(f"Generated {OUTPUT} with {len(package['cards'])} medical cards")


if __name__ == "__main__":
    main()
