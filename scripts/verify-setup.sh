#!/usr/bin/env bash
#
# verify-setup.sh - post-install audit of a Mac built from this repo.
#
# Everything is read from data/install-groups.json (the single source of truth) and
# apply-macos-defaults.sh, so adding an app to the data file automatically adds it here.
# Read-only: it changes nothing.
#
# Usage:
#   scripts/verify-setup.sh [BUNDLE]        BUNDLE defaults to "workstation"
#                                           (any bundle id in data/install-groups.json)
#   scripts/verify-setup.sh --list          print the bundle ids and exit
#
# Checks: Homebrew formulae, casks and taps of the bundle's groups; Mac App Store apps if
# a group carries an optional "mas" list (IDs or {"id":..}); macOS defaults via
# `apply-macos-defaults.sh --check`. A tap-qualified name (user/tap/foo) matches the
# installed short name "foo". For what is installed but NOT in the repo, use drift-report.sh.
#
# Exit status: 0 all good, 1 something missing or mismatched, 2 usage/environment error.
# Works with macOS /bin/bash 3.2 (no mapfile, no associative arrays) and python3 stdlib.

set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
data_file="$repo_root/data/install-groups.json"

if [[ ! -f "$data_file" ]]; then
  echo "Missing data file: $data_file" >&2
  exit 2
fi
command -v python3 >/dev/null 2>&1 || { echo "python3 is required." >&2; exit 2; }

if [[ "${1:-}" == "--list" ]]; then
  python3 -c 'import json,sys
for b in json.load(open(sys.argv[1]))["bundles"]: print(b["id"], "-", b.get("description",""))' "$data_file"
  exit 0
fi
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  sed -n '3,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; /^#!/d'
  exit 0
fi

bundle="${1:-workstation}"

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is not installed." >&2
  exit 2
fi

# Expected items as "kind:name" lines: formula, cask, tap, mas.
expected="$(
  python3 - "$data_file" "$bundle" <<'PY'
import json, sys

data_path, bundle_id = sys.argv[1], sys.argv[2]
with open(data_path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

groups = {group["id"]: group for group in data["groups"]}
bundle = next((item for item in data["bundles"] if item["id"] == bundle_id), None)
if bundle is None:
    ids = ", ".join(b["id"] for b in data["bundles"])
    sys.stderr.write("Unknown bundle: %s (available: %s)\n" % (bundle_id, ids))
    sys.exit(2)

seen = set()
for group_id in bundle["include"]:
    g = groups[group_id]
    for kind, key in (("tap", "taps"), ("formula", "formulae"), ("cask", "casks"), ("mas", "mas")):
        for item in g.get(key, []):
            name = str(item["id"]) if isinstance(item, dict) else str(item)
            if (kind, name) not in seen:
                seen.add((kind, name))
                print("%s:%s" % (kind, name))
PY
)" || exit 2

# One brew call per kind, then plain grep -Fx lookups (fast, bash 3.2 safe).
installed_formulae="$(brew list --formula 2>/dev/null)"
installed_casks="$(brew list --cask 2>/dev/null)"
installed_taps="$(brew tap 2>/dev/null)"
installed_mas=""
command -v mas >/dev/null 2>&1 && installed_mas="$(mas list 2>/dev/null | awk '{print $1}')"

has() { printf '%s\n' "$2" | grep -Fxq -- "$1"; }

failures=0
missing_formulae="" missing_casks="" missing_taps="" missing_mas=""

while IFS= read -r entry; do
  [[ -z "$entry" ]] && continue
  kind="${entry%%:*}"
  name="${entry#*:}"
  short="${name##*/}"
  case "$kind" in
    formula) has "$short" "$installed_formulae" || missing_formulae="$missing_formulae  - $name"$'\n' ;;
    cask)    has "$short" "$installed_casks"    || missing_casks="$missing_casks  - $name"$'\n' ;;
    tap)     has "$name" "$installed_taps"      || missing_taps="$missing_taps  - $name"$'\n' ;;
    mas)
      if ! command -v mas >/dev/null 2>&1; then
        missing_mas="$missing_mas  - $name (mas not installed)"$'\n'
      else
        has "$name" "$installed_mas" || missing_mas="$missing_mas  - $name"$'\n'
      fi
      ;;
  esac
done <<<"$expected"

report() { # title, list
  if [[ -n "$2" ]]; then
    failures=1
    printf '%s\n%s' "$1" "$2"
  fi
}
report "Missing taps:" "$missing_taps"
report "Missing formulae:" "$missing_formulae"
report "Missing casks:" "$missing_casks"
report "Missing Mac App Store apps:" "$missing_mas"

# macOS defaults come from the one script that defines them.
"$repo_root/scripts/apply-macos-defaults.sh" --check || failures=1

if [[ "$failures" -eq 0 ]]; then
  cat <<EOT
Bundle "$bundle" looks good.

Validated (all from data/install-groups.json):
- Homebrew taps, formulae and casks
- Mac App Store apps (when the data lists any)
- macOS defaults (apply-macos-defaults.sh --check)

Manual checks still worth doing:
- Three-finger drag
- Vivaldi default browser and DuckDuckGo search
- Keyboard Maestro shortcut wiring
EOT
  exit 0
fi

exit 1
