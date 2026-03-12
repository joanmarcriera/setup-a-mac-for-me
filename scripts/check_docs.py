#!/usr/bin/env python3

from __future__ import annotations

import pathlib
import sys
from html.parser import HTMLParser
from urllib.parse import urlparse


ROOT = pathlib.Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"
REQUIRED_FILES = [
    DOCS / "index.html",
    DOCS / "404.html",
    DOCS / "CNAME",
    DOCS / ".nojekyll",
    DOCS / "assets" / "style.css",
    DOCS / "assets" / "app.js",
    DOCS / "assets" / "homebrew.js",
    DOCS / "assets" / "search.js",
    DOCS / "assets" / "install-groups.json",
    DOCS / "assets" / "search-index.json",
]


class ReferenceParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.references: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        for name, value in attrs:
            if name in {"href", "src"} and value:
                self.references.append(value)


def is_local_reference(reference: str) -> bool:
    if reference.startswith(("#", "mailto:", "tel:")):
        return False
    parsed = urlparse(reference)
    return not parsed.scheme and not reference.startswith("//")


def target_for(page: pathlib.Path, reference: str) -> pathlib.Path:
    clean_ref = reference.split("#", 1)[0].split("?", 1)[0]
    return (page.parent / clean_ref).resolve()


def main() -> int:
    missing: list[str] = []

    for required in REQUIRED_FILES:
        if not required.exists():
            missing.append(str(required.relative_to(ROOT)))

    for page in DOCS.glob("*.html"):
        parser = ReferenceParser()
        parser.feed(page.read_text(encoding="utf-8"))
        for reference in parser.references:
            if not is_local_reference(reference):
                continue
            target = target_for(page, reference)
            if not target.exists():
                missing.append(f"{page.relative_to(ROOT)} -> {reference}")

    if missing:
        print("Missing documentation targets:", file=sys.stderr)
        for item in missing:
            print(f"- {item}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
