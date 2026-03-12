#!/usr/bin/env bash

set -euo pipefail

bundle="${1:-workstation}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
data_file="$repo_root/data/install-groups.json"

if [[ ! -f "$data_file" ]]; then
  echo "Missing data file: $data_file" >&2
  exit 1
fi

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is not installed." >&2
  exit 1
fi

mapfile -t expected < <(
  python3 - "$data_file" "$bundle" <<'PY'
import json
import sys

data_path, bundle_id = sys.argv[1], sys.argv[2]
with open(data_path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

groups = {group["id"]: group for group in data["groups"]}
bundle = next((item for item in data["bundles"] if item["id"] == bundle_id), None)
if bundle is None:
    raise SystemExit(f"Unknown bundle: {bundle_id}")

formulae = []
casks = []
for group_id in bundle["include"]:
    formulae.extend(groups[group_id]["formulae"])
    casks.extend(groups[group_id]["casks"])

seen = set()
for formula in formulae:
    if formula not in seen:
        print(f"formula:{formula}")
        seen.add(formula)

seen = set()
for cask in casks:
    if cask not in seen:
        print(f"cask:{cask}")
        seen.add(cask)
PY
)

mapfile -t installed_formulae < <(brew list --formula)
mapfile -t installed_casks < <(brew list --cask)

missing_formulae=()
missing_casks=()

contains() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    if [[ "$item" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

for entry in "${expected[@]}"; do
  kind="${entry%%:*}"
  name="${entry#*:}"
  if [[ "$kind" == "formula" ]]; then
    contains "$name" "${installed_formulae[@]}" || missing_formulae+=("$name")
  else
    contains "$name" "${installed_casks[@]}" || missing_casks+=("$name")
  fi
done

read_default() {
  local domain="$1"
  local key="$2"
  defaults read "$domain" "$key" 2>/dev/null || true
}

failures=0

if [[ "${#missing_formulae[@]}" -gt 0 ]]; then
  failures=1
  echo "Missing formulae:"
  printf '  - %s\n' "${missing_formulae[@]}"
fi

if [[ "${#missing_casks[@]}" -gt 0 ]]; then
  failures=1
  echo "Missing casks:"
  printf '  - %s\n' "${missing_casks[@]}"
fi

declare -A defaults_expect=(
  ["com.apple.dock:autohide-time-modifier"]="0.5"
  ["com.apple.dock:autohide-delay"]="0"
  ["com.apple.dock:springboard-columns"]="10"
  ["com.apple.dock:springboard-rows"]="8"
)

for compound in "${!defaults_expect[@]}"; do
  domain="${compound%%:*}"
  key="${compound#*:}"
  value="$(read_default "$domain" "$key")"
  if [[ "$value" != "${defaults_expect[$compound]}" ]]; then
    failures=1
    echo "Default mismatch: $domain $key expected ${defaults_expect[$compound]}, got ${value:-<unset>}"
  fi
done

if [[ "$failures" -eq 0 ]]; then
  cat <<EOF
Bundle "$bundle" looks good.

Validated:
- Homebrew formulae and casks from data/install-groups.json
- Dock autohide timing
- Launchpad grid size

Manual checks still worth doing:
- Tap to Click and three-finger drag
- Vivaldi default browser and DuckDuckGo search
- Keyboard Maestro shortcut wiring
EOF
  exit 0
fi

exit 1
