#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import pathlib
import sys
from html.parser import HTMLParser


ROOT = pathlib.Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"
DATA_PATH = ROOT / "data" / "install-groups.json"
OUTPUT_PATH = DOCS / "assets" / "search-index.json"
EXCLUDED_DOCS = {"404.html"}


class DocParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self._tag_stack: list[str] = []
        self._ignore_depth = 0
        self.title_parts: list[str] = []
        self.description = ""
        self.headings: list[str] = []
        self.body_parts: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        self._tag_stack.append(tag)
        if tag in {"script", "style"}:
            self._ignore_depth += 1
            return
        if tag == "meta":
            attr_map = {name: value for name, value in attrs}
            if attr_map.get("name") == "description" and attr_map.get("content"):
                self.description = attr_map["content"].strip()

    def handle_endtag(self, tag: str) -> None:
        if tag in {"script", "style"} and self._ignore_depth:
            self._ignore_depth -= 1
        if self._tag_stack:
            self._tag_stack.pop()

    def handle_data(self, data: str) -> None:
        if self._ignore_depth:
            return
        text = " ".join(data.split())
        if not text:
            return
        current = self._tag_stack[-1] if self._tag_stack else ""
        if current == "title":
            self.title_parts.append(text)
        if current in {"h1", "h2", "h3"}:
            self.headings.append(text)
        if current in {"p", "li", "code", "h1", "h2", "h3", "title", "small", "span", "strong"}:
            self.body_parts.append(text)


def parse_doc(path: pathlib.Path) -> dict[str, str]:
    parser = DocParser()
    parser.feed(path.read_text(encoding="utf-8"))
    title = " ".join(parser.title_parts).strip() or path.stem.replace("-", " ").title()
    body = " ".join(parser.body_parts).strip()
    headings = " ".join(parser.headings).strip()
    return {
        "kind": "page",
        "title": title,
        "url": path.name,
        "summary": parser.description,
        "body": " ".join(part for part in [headings, body] if part).strip(),
    }


def load_install_data() -> dict:
    with DATA_PATH.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def build_package_entries(data: dict) -> list[dict[str, str]]:
    entries: list[dict[str, str]] = []

    for bundle in data.get("bundles", []):
        entries.append(
            {
                "kind": "bundle",
                "title": bundle["label"],
                "url": "homebrew.html",
                "summary": bundle["description"],
                "body": " ".join(bundle["include"]),
            }
        )

    for group in data.get("groups", []):
        package_text = " ".join(group["formulae"] + group["casks"])
        note_text = " ".join(group.get("notes", []))
        entries.append(
            {
                "kind": "group",
                "title": group["label"],
                "url": "homebrew.html",
                "summary": group["description"],
                "body": " ".join(part for part in [package_text, note_text] if part).strip(),
            }
        )

        for package in group["formulae"]:
            entries.append(
                {
                    "kind": "formula",
                    "title": package,
                    "url": "homebrew.html",
                    "summary": f'Homebrew formula in {group["label"]}',
                    "body": " ".join(part for part in [group["description"], note_text] if part).strip(),
                }
            )
        for package in group["casks"]:
            entries.append(
                {
                    "kind": "cask",
                    "title": package,
                    "url": "homebrew.html",
                    "summary": f'Homebrew cask in {group["label"]}',
                    "body": " ".join(part for part in [group["description"], note_text] if part).strip(),
                }
            )

    return entries


def build_index() -> list[dict[str, str]]:
    entries = [
        parse_doc(path)
        for path in sorted(DOCS.glob("*.html"))
        if path.name not in EXCLUDED_DOCS
    ]
    entries.extend(build_package_entries(load_install_data()))
    return entries


def write_or_check(entries: list[dict[str, str]], check: bool) -> int:
    content = json.dumps(entries, indent=2) + "\n"
    if check:
        current = OUTPUT_PATH.read_text(encoding="utf-8") if OUTPUT_PATH.exists() else None
        if current != content:
            print("Search index is out of date: docs/assets/search-index.json", file=sys.stderr)
            return 1
        return 0

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(content, encoding="utf-8")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Build the client-side search index for the docs site.")
    parser.add_argument("--check", action="store_true", help="Fail if the generated search index is out of date.")
    args = parser.parse_args()
    return write_or_check(build_index(), args.check)


if __name__ == "__main__":
    raise SystemExit(main())
