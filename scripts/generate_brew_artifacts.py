#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import pathlib
import sys
from collections import OrderedDict


ROOT = pathlib.Path(__file__).resolve().parent.parent
DATA_PATH = ROOT / "data" / "install-groups.json"
BREW_DIR = ROOT / "brew"
DOCS_DATA_PATH = ROOT / "docs" / "assets" / "install-groups.json"


def load_data() -> dict:
    with DATA_PATH.open("r", encoding="utf-8") as handle:
        data = json.load(handle)

    groups = data.get("groups", [])
    bundles = data.get("bundles", [])
    group_ids = [group["id"] for group in groups]

    if len(group_ids) != len(set(group_ids)):
        raise ValueError("Group ids must be unique.")

    for bundle in bundles:
        unknown = [item for item in bundle["include"] if item not in group_ids]
        if unknown:
            raise ValueError(f"Bundle {bundle['id']} references unknown groups: {unknown}")

    return data


def unique(items: list[str]) -> list[str]:
    return list(OrderedDict.fromkeys(items))


def brewfile_contents(label: str, description: str, formulae: list[str], casks: list[str]) -> str:
    lines = [f"# {description}"]
    if formulae:
        for formula in formulae:
            lines.append(f'brew "{formula}"')
    if casks:
        if formulae:
            lines.append("")
        for cask in casks:
            lines.append(f'cask "{cask}"')
    lines.append("")
    return "\n".join(lines)


def collect_bundle_items(bundle: dict, groups_by_id: dict[str, dict]) -> tuple[list[str], list[str]]:
    formulae: list[str] = []
    casks: list[str] = []

    for group_id in bundle["include"]:
        group = groups_by_id[group_id]
        formulae.extend(group["formulae"])
        casks.extend(group["casks"])

    return unique(formulae), unique(casks)


def brew_commands(formulae: list[str], casks: list[str]) -> list[str]:
    commands: list[str] = []
    if formulae:
        commands.append(f"brew install {' '.join(formulae)}")
    if casks:
        commands.append(f"brew install --cask {' '.join(casks)}")
    return commands


def render_brew_readme(data: dict) -> str:
    groups = data["groups"]
    bundles = data["bundles"]

    sections = [
        "# Homebrew Install Commands",
        "",
        "This folder is generated from `data/install-groups.json`.",
        "",
        "Copy and paste the commands you want.",
        "",
        "The default bundles are listed first, followed by the smaller group commands.",
        "",
        "## Default Bundles",
        "",
    ]

    groups_by_id = {group["id"]: group for group in groups}

    for bundle in bundles:
        formulae, casks = collect_bundle_items(bundle, groups_by_id)
        sections.extend(
            [
                f"### {bundle['label']}",
                "",
                bundle["description"],
                "",
                "```sh",
                "\n".join(brew_commands(formulae, casks)),
                "```",
                "",
            ]
        )

    sections.extend(["## Individual Groups", ""])

    for group in groups:
        sections.extend(
            [
                f"### {group['label']}",
                "",
                group["description"],
                "",
            ]
        )
        sections.extend(["```sh", "\n".join(brew_commands(group["formulae"], group["casks"])), "```", ""])

    notes = unique(
        [
            note
            for group in groups
            for note in group.get("notes", [])
        ]
    )
    notes.extend(
        [
            "Alfred, Raycast, `pnpm`, Dropover, iBar, Whimsical, and Notion are intentionally excluded."
        ]
    )

    sections.extend(["## Notes", ""])
    for note in unique(notes):
        sections.append(f"- {note}")
    sections.append("")

    return "\n".join(sections)


def build_targets(data: dict) -> dict[pathlib.Path, str]:
    groups_by_id = {group["id"]: group for group in data["groups"]}
    targets: dict[pathlib.Path, str] = {}

    for group in data["groups"]:
        targets[BREW_DIR / f"Brewfile.{group['id']}"] = brewfile_contents(
            group["label"],
            group["description"],
            group["formulae"],
            group["casks"],
        )

    for bundle in data["bundles"]:
        formulae, casks = collect_bundle_items(bundle, groups_by_id)
        targets[BREW_DIR / f"Brewfile.{bundle['id']}"] = brewfile_contents(
            bundle["label"],
            bundle["description"],
            formulae,
            casks,
        )

    targets[BREW_DIR / "README.md"] = render_brew_readme(data)
    targets[DOCS_DATA_PATH] = json.dumps(data, indent=2) + "\n"
    return targets


def write_or_check(targets: dict[pathlib.Path, str], check: bool) -> int:
    mismatches: list[pathlib.Path] = []

    for path, content in targets.items():
        if check:
            current = path.read_text(encoding="utf-8") if path.exists() else None
            if current != content:
                mismatches.append(path)
            continue

        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    if check and mismatches:
        print("Generated files are out of date:", file=sys.stderr)
        for path in mismatches:
            print(f"- {path.relative_to(ROOT)}", file=sys.stderr)
        return 1

    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Homebrew artifacts for the repo and site.")
    parser.add_argument("--check", action="store_true", help="Fail if generated files do not match the source data.")
    args = parser.parse_args()

    try:
        data = load_data()
        targets = build_targets(data)
        return write_or_check(targets, args.check)
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
