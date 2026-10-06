#!/usr/bin/env bash
#
# drift-report.sh - "what changed since I set this Mac up?"
#
# Compares what is installed (Homebrew leaves, casks, Mac App Store apps) with the
# install groups in data/install-groups.json and prints:
#   1. installed but NOT in the repo   (you added it by hand)
#   2. in the repo but NOT installed   (removed, or never installed)
#   3. copy/paste suggestions to close each gap
#
# Read-only: it only runs `brew leaves`, `brew list`, `mas list` and reads the JSON.
# Needs bash 3.2+ and python3 (stdlib only). Typically < 2 s.
#
# Usage:
#   scripts/drift-report.sh [--json] [--bundle ID] [--ignore FILE] [--no-mas] [-h]
#
#   --json         machine-readable output (one JSON object) instead of text
#   --bundle ID    only compare against the groups of one bundle (e.g. workstation);
#                  default is every group in the data file
#   --ignore FILE  names to ignore, one per line ('#' comments ok). Defaults to
#                  ~/.config/mac-drift-ignore when that file exists. Use it for tools you
#                  deliberately keep out of the repo.
#   --no-mas       skip the Mac App Store comparison
#
# Exit status: 0 no drift, 1 drift found, 2 error (missing brew/python3/data file).
# That makes it cron/launchd friendly:  drift-report.sh --json >/tmp/drift.json || notify ...
#
# Matching rules: tap-qualified names (steipete/tap/foo) match on their last path
# component; a repo formula counts as installed if it is installed at all (leaf or
# dependency), while "installed but not in repo" only considers leaves, so ordinary
# dependencies never show up as drift. Optional data keys, if present, are honoured:
# group "mas" (list of app IDs or {"id":..,"name":..}) and group "taps".

set -u
set -o pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
data_file="$repo_root/data/install-groups.json"
as_json=0
bundle=""
ignore_file=""
use_mas=1

usage() { sed -n '3,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; /^#!/d'; }

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --json) as_json=1 ;;
    --bundle) shift; bundle="${1:-}" ;;
    --ignore) shift; ignore_file="${1:-}" ;;
    --no-mas) use_mas=0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

[[ -f "$data_file" ]] || { echo "Missing data file: $data_file" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required." >&2; exit 2; }
command -v brew >/dev/null 2>&1 || { echo "Homebrew is not installed." >&2; exit 2; }

if [[ -z "$ignore_file" && -f "$HOME/.config/mac-drift-ignore" ]]; then
  ignore_file="$HOME/.config/mac-drift-ignore"
fi

# Never let a read-only report trigger a brew self-update or analytics call.
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1

leaves="$(brew leaves 2>/dev/null)"
formulae="$(brew list --formula 2>/dev/null)"
casks="$(brew list --cask 2>/dev/null)"
taps="$(brew tap 2>/dev/null)"
mas_list=""
if [[ "$use_mas" -eq 1 ]] && command -v mas >/dev/null 2>&1; then
  mas_list="$(mas list 2>/dev/null)"
fi

LEAVES="$leaves" FORMULAE="$formulae" CASKS="$casks" TAPS="$taps" MAS="$mas_list" \
  python3 - "$data_file" "$as_json" "$bundle" "$ignore_file" "$use_mas" <<'PY'
import json, os, re, sys

data_path, as_json, bundle_id, ignore_path, use_mas = sys.argv[1:6]
as_json = as_json == "1"


def lines(name):
    return [l.strip() for l in os.environ.get(name, "").splitlines() if l.strip()]


def base(name):
    """steipete/tap/foo -> foo (taps qualify names; installed lists are short)."""
    return name.rsplit("/", 1)[-1]


def die(msg):
    # Exit 2 = error, so cron can tell "broken" from "drift" (exit 1).
    sys.stderr.write(msg + "\n")
    sys.exit(2)


try:
    with open(data_path, encoding="utf-8") as fh:
        data = json.load(fh)
except (OSError, ValueError) as exc:
    die("Cannot read %s: %s" % (data_path, exc))

groups = data.get("groups", [])
if bundle_id:
    b = next((x for x in data.get("bundles", []) if x["id"] == bundle_id), None)
    if b is None:
        die("Unknown bundle: %s" % bundle_id)
    keep = set(b["include"])
    groups = [g for g in groups if g["id"] in keep]

ignore = set()
if ignore_path and os.path.isfile(ignore_path):
    with open(ignore_path, encoding="utf-8") as fh:
        for l in fh:
            l = l.split("#", 1)[0].strip()
            if l:
                ignore.add(base(l))

# repo side: name -> group id (first group wins for the suggestion)
repo_f, repo_c, repo_m, repo_t = {}, {}, {}, {}
for g in groups:
    for n in g.get("formulae", []):
        repo_f.setdefault(base(n), (g["id"], n))
    for n in g.get("casks", []):
        repo_c.setdefault(base(n), (g["id"], n))
    for t in g.get("taps", []):
        repo_t.setdefault(t, g["id"])
    for m in g.get("mas", []):
        mid, mname = (str(m["id"]), m.get("name", "")) if isinstance(m, dict) else (str(m), "")
        repo_m.setdefault(mid, (g["id"], mname))

# installed side
leaves = {base(n) for n in lines("LEAVES")}
all_formulae = {base(n) for n in lines("FORMULAE")} | leaves
casks = {base(n) for n in lines("CASKS")}
taps = set(lines("TAPS"))
mas = {}
for l in lines("MAS"):  # "  497799835  Xcode  (16.1)"
    m = re.match(r"(\d+)\s+(.+?)\s+\(([^()]*)\)\s*$", l)
    if m:
        mas[m.group(1)] = m.group(2)

drift = {
    "extra_formulae": sorted(n for n in leaves if n not in repo_f and n not in ignore),
    "missing_formulae": sorted(n for n in repo_f if n not in all_formulae and n not in ignore),
    "extra_casks": sorted(n for n in casks if n not in repo_c and n not in ignore),
    "missing_casks": sorted(n for n in repo_c if n not in casks and n not in ignore),
    "extra_mas": [],
    "missing_mas": [],
    "missing_taps": sorted(t for t in repo_t if t not in taps),
}
if use_mas == "1" and os.environ.get("MAS"):
    drift["extra_mas"] = sorted(
        ({"id": i, "name": n} for i, n in mas.items() if i not in repo_m and i not in ignore),
        key=lambda d: d["name"].lower())
    drift["missing_mas"] = sorted(
        ({"id": i, "name": repo_m[i][1]} for i in repo_m if i not in mas and i not in ignore),
        key=lambda d: d["id"])

# suggestions
sug = []
if drift["missing_taps"]:
    sug.append("brew tap " + " ".join(drift["missing_taps"]))
if drift["missing_formulae"]:
    sug.append("brew install " + " ".join(repo_f[n][1] for n in drift["missing_formulae"]))
if drift["missing_casks"]:
    sug.append("brew install --cask " + " ".join(repo_c[n][1] for n in drift["missing_casks"]))
if drift["missing_mas"]:
    sug.append("mas install " + " ".join(d["id"] for d in drift["missing_mas"]))
add = []
if drift["extra_formulae"]:
    add.append('"formulae": [%s]' % ", ".join('"%s"' % n for n in drift["extra_formulae"]))
if drift["extra_casks"]:
    add.append('"casks": [%s]' % ", ".join('"%s"' % n for n in drift["extra_casks"]))
if add:
    sug.append("# adopt into the repo: add to a group in data/install-groups.json, then regenerate:\n"
               "#   " + "; ".join(add) + "\n"
               "#   python3 scripts/generate_brew_artifacts.py && python3 scripts/build_search_index.py")
if drift["extra_mas"]:
    sug.append("# Mac App Store apps not tracked (the data file has no 'mas' list yet): "
               + ", ".join("%s (%s)" % (d["name"], d["id"]) for d in drift["extra_mas"]))

has_drift = any(drift[k] for k in drift)

if as_json:
    print(json.dumps({"drift": has_drift, "bundle": bundle_id or None, **drift,
                      "suggestions": sug}, indent=2))
else:
    def section(title, items, fmt=str):
        print("%s (%d)" % (title, len(items)))
        for i in items:
            print("  " + fmt(i))
        if not items:
            print("  none")
        print()
    section("Installed but not in the repo - formulae (leaves)", drift["extra_formulae"])
    section("Installed but not in the repo - casks", drift["extra_casks"])
    if use_mas == "1" and os.environ.get("MAS"):
        section("Installed but not in the repo - Mac App Store", drift["extra_mas"],
                lambda d: "%s  %s" % (d["id"], d["name"]))
    section("In the repo but not installed - formulae", drift["missing_formulae"])
    section("In the repo but not installed - casks", drift["missing_casks"])
    section("In the repo but not installed - taps", drift["missing_taps"])
    if drift["missing_mas"]:
        section("In the repo but not installed - Mac App Store", drift["missing_mas"],
                lambda d: "%s  %s" % (d["id"], d["name"]))
    print("Suggestions")
    print("\n".join("  " + s.replace("\n", "\n  ") for s in sug) if sug else "  none - no drift")
sys.exit(1 if has_drift else 0)
PY
