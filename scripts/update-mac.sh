#!/usr/bin/env bash
#
# update-mac: safe, incremental upgrade of a Mac built from this repo.
#
# Usage:  update-mac [--dry-run] [--greedy-casks] [--yes] [--with-macos] [--skip-backup-check] [--skip-macos] [--ask] [--major] [--verbose]
#         (see --help for the full option list; README.md documents the behaviour)
#
# Works with macOS /bin/bash 3.2 (no associative arrays, no mapfile). Copy to ~/bin to use:
#   cp scripts/update-mac.sh ~/bin/update-mac && chmod +x ~/bin/update-mac

set -u
set -o pipefail

failures=0
use_greedy_casks=false
assume_yes=false
yes_flag=false     # --yes was passed (vs. assume_yes, which the [A]ll answer also sets)
with_macos=false   # --with-macos: let --yes also run the macOS software update
skip_backup_check=false
skip_macos=false
dry_run=false
classic_prompts=false  # --ask: per-tool prompts instead of the selection screen
verbose=false          # --verbose: list routine updates in the plan table too
include_major=false    # --major (or `m` on the selection screen): do not hold back major jumps

# Selection screen result: with selection_mode on, begin_domain runs exactly the tools
# whose label is in selected_labels ("|Homebrew|npm|"), with no further prompts.
selection_mode=false
selected_labels=""

# Execution order; domain_cmds[i] is the command that must exist for domain_labels[i].
domain_labels=("Cleanup" "Homebrew" "npm" "Mac App Store" "uv" "pipx" "Volta" "rustup" "mise" "macOS")
domain_cmds=(volta brew npm mas uv pipx volta rustup mise softwareupdate)

# Per-run scratch dir (scan results). The slow `softwareupdate -l` scan is started in
# the background and joined later, so it overlaps with every other pre-flight check.
scan_dir=$(mktemp -d "${TMPDIR:-/tmp}/update-mac.XXXXXX") || exit 2
trap 'rm -rf "$scan_dir"' EXIT
trap 'exit 130' INT TERM
softwareupdate_pid=""

# Per-tool outcome table, printed at the end.
current_domain=""
current_failures=0
domain_results=""

# Captured once by the pre-flight summary and reused by the macOS step so the
# slow `softwareupdate -l` network scan only runs a single time per invocation.
softwareupdate_list_output=""
softwareupdate_list_captured=false

usage() {
  cat <<'EOF'
Usage: update-mac [--dry-run] [--greedy-casks] [--yes] [--with-macos] [--skip-backup-check] [--skip-macos] [--ask] [--major] [--verbose]

Default behavior:
- Prints a pre-flight summary (system status + pending update counts) before touching anything.
- Refuses to upgrade anything unless Time Machine has a latest backup (warns after 2 days,
  refuses after 7) and a visible destination.
- Also lists "Needs attention": deprecated/disabled packages, broken Volta packages and dangling
  symlinks. Broken Volta packages can be removed via the "Cleanup" entry (never by --yes).
- Scans every tool in parallel, then shows an upgrade-plan table (risky updates first).
- Shows a selection screen (arrows/j,k move, space toggles, a all, n none, Enter runs,
  q quits). Enter is the one approval: the ticked tools then run one step at a time with
  no further prompts. (--ask restores the old per-tool prompts.)
- Updates Homebrew without forcing auto-updating casks.

Options:
  -n, --dry-run        Preview every step and mutate nothing. Shows the summary and what each
                       tool would do, then exits. Skips the Time Machine gate (nothing changes).
  --greedy-casks       Force Homebrew to upgrade auto-updating casks too (alias: --greedy).
  -y, --yes            Run mutating steps without interactive approval.
  --skip-backup-check  Skip the Time Machine safety gate. Use when Terminal lacks
                       Full Disk Access and tmutil latestbackup cannot run.
  --with-macos         With --yes, also run `softwareupdate -i -a`. Without it, --yes leaves macOS alone.
  --skip-macos         Do not run (or offer) the macOS update; still lists what is pending.
                       Useful when a major macOS upgrade is listed and you want to do it by hand.
  --major              Also upgrade major version jumps (npm 11 -> 12, Node 24 -> 26, ...). By default
                       they are shown in the plan but held back, so nothing big changes unasked.
  --ask                Ask per tool (Yes/No/Skip/All/Quit) instead of the selection screen.
  -v, --verbose        List routine (same-major) updates in the plan table as well.
  -h, --help           Show this help.

macOS: never pre-ticked on the selection screen; --yes skips it unless --with-macos is given.
Major macOS upgrades are never installed by this script; only same-major updates are.
EOF
}

log() {
  printf '\n==> %s\n' "$1"
}

note() {
  printf '%s\n' "$1"
}

# Preview-style hint: pointless once the selection screen has shown the plan.
hint() {
  [[ "$selection_mode" == true ]] || note "$1"
}

run_step() {
  local label="$1"
  shift

  log "$label"
  if "$@"; then
    printf 'Done: %s\n' "$label"
  else
    printf 'Failed: %s\n' "$label" >&2
    failures=$((failures + 1))
    return 1
  fi
}

# Like run_step, but a non-zero exit is reported without counting as a failure.
# For diagnostics (brew doctor, mise doctor, rustup check) that exit non-zero to
# *report* something rather than because the update broke.
run_info() {
  local label="$1"
  shift

  log "$label"
  if "$@"; then
    printf 'Done: %s\n' "$label"
  else
    printf 'Reported issues (exit %s, not counted as a failure): %s\n' "$?" "$label"
  fi
}

preview_step() {
  local label="$1"
  shift
  local output=""
  local status=0

  # The plan table already covers what a preview would show.
  [[ "$selection_mode" == true ]] && return 0

  log "$label"
  if output="$("$@" 2>&1)"; then
    status=0
  else
    status=$?
  fi

  if [[ -n "$output" ]]; then
    printf '%s\n' "$output"
  elif [[ "$status" -eq 0 ]]; then
    printf 'No pending changes reported.\n'
  else
    printf 'Preview command exited with status %s.\n' "$status"
  fi
}

ensure_prompt_available() {
  if [[ "$dry_run" == true || "$assume_yes" == true ]]; then
    return 0
  fi
  # Prompts read /dev/tty, so test that it actually opens (stdin may be piped).
  if ! { : </dev/tty; } 2>/dev/null; then
    printf 'Interactive approval is the default, but no terminal prompt is available. Re-run with --yes to auto-approve mutating steps, or --dry-run to preview only.\n' >&2
    exit 2
  fi
}

# Returns: 0 yes, 1 no, 2 skip, 3 quit, 4 read-error, 5 all (yes + auto-approve the rest).
prompt_for_step() {
  local label="$1"
  local reply=""
  local normalized=""

  if [[ "$assume_yes" == true ]]; then
    return 0
  fi

  while true; do
    printf 'Run "%s"? [Y]es/[n]o/[s]kip/[a]ll/[q]uit (default yes): ' "$label" >/dev/tty
    if ! IFS= read -r reply </dev/tty; then
      return 4
    fi

    normalized=$(printf '%s' "$reply" | tr '[:upper:]' '[:lower:]')
    case "$normalized" in
      y|yes|"")
        return 0
        ;;
      n|no)
        return 1
        ;;
      s|skip)
        return 2
        ;;
      a|all)
        return 5
        ;;
      q|quit)
        return 3
        ;;
      *)
        printf 'Enter yes, no, skip, all, or quit.\n' >/dev/tty
        ;;
    esac
  done
}

# Gate a whole tool with a single decision. Returns 0 to run the tool's mutating
# block, 1 to skip it. Handles dry-run, --yes, and the [A]ll prompt option.
begin_domain_gate() {
  local label="$1"
  local steps="$2"
  local prompt_status=0

  if [[ "$dry_run" == true ]]; then
    log "$label"
    printf '[dry-run] Would run: %s\n' "$steps"
    return 1
  fi

  # Selection screen already approved a set of tools: run those, skip the rest.
  if [[ "$selection_mode" == true ]]; then
    case "$selected_labels" in
      *"|$label|"*) return 0 ;;
      *)
        printf 'Not selected: %s\n' "$label"
        return 1
        ;;
    esac
  fi

  if [[ "$assume_yes" == true ]]; then
    return 0
  fi

  prompt_for_step "$label ($steps)"
  prompt_status=$?

  case "$prompt_status" in
    0)
      return 0
      ;;
    5)
      assume_yes=true
      note "Approving this and every remaining tool without further prompts."
      return 0
      ;;
    1)
      printf 'Not run: %s\n' "$label"
      return 1
      ;;
    2)
      printf 'Skipped: %s\n' "$label"
      return 1
      ;;
    3)
      printf 'Quit requested. Stopping before: %s\n' "$label" >&2
      exit 130
      ;;
    *)
      printf 'Prompt failed. Stopping before: %s\n' "$label" >&2
      exit 2
      ;;
  esac
}

# Record how the tool that just ran went (failures counted since it started).
close_domain() {
  local status="ok"

  [[ -z "$current_domain" ]] && return 0
  [[ "$failures" -gt "$current_failures" ]] && status="FAILED ($((failures - current_failures)) step(s))"
  domain_results="${domain_results}${current_domain}|${status}"$'\n'
  current_domain=""
}

# begin_domain_gate decides; this wrapper also tracks results for the final table.
begin_domain() {
  close_domain
  begin_domain_gate "$@" || return 1
  current_domain="$1"
  current_failures=$failures
  return 0
}

print_results_table() {
  local label status

  [[ -z "$domain_results" ]] && return 0
  log "Results"
  while IFS='|' read -r label status; do
    [[ -n "$label" ]] && printf '  %-14s %s\n' "$label" "$status"
  done <<<"$domain_results"
}

missing_tool() {
  local name="$1"
  local install_cmd="$2"
  local learn_url="$3"

  printf 'Not installed: %s. Install with: %s. Learn more: %s\n' "$name" "$install_cmd" "$learn_url"
}

require_time_machine_backup() {
  local latest_backup
  local destination_info

  log "Time Machine safety gate"

  if ! command -v tmutil >/dev/null 2>&1; then
    printf 'Failed: tmutil is not available, so the backup gate cannot run.\n' >&2
    return 1
  fi

  if ! latest_backup=$(tmutil latestbackup 2>&1); then
    printf 'Failed: tmutil latestbackup did not return a usable backup.\n' >&2
    printf '%s\n' "$latest_backup" >&2
    printf 'If Terminal lacks Full Disk Access, grant it in System Settings → Privacy & Security → Full Disk Access,\n' >&2
    printf 'or re-run with --skip-backup-check to bypass this gate.\n' >&2
    printf 'Aborting before any upgrades.\n' >&2
    return 1
  fi

  if ! destination_info=$(tmutil destinationinfo 2>&1); then
    printf 'Failed: tmutil destinationinfo could not confirm a Time Machine destination.\n' >&2
    printf '%s\n' "$destination_info" >&2
    printf 'Aborting before any upgrades.\n' >&2
    return 1
  fi

  printf 'Latest backup: %s\n' "$latest_backup"
  printf 'Time Machine destination confirmed.\n'

  # A "latest backup" from months ago is not a safety net. Warn after 2 days,
  # refuse after 7. Skipped quietly if the timestamp cannot be parsed.
  local stamp epoch age
  stamp=$(basename "$latest_backup" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}' | tail -n1)
  if [[ -n "$stamp" ]] && epoch=$(date -j -f '%Y-%m-%d-%H%M%S' "$stamp" '+%s' 2>/dev/null); then
    age=$(( $(date '+%s') - epoch ))
    if [[ "$age" -gt 604800 ]]; then
      printf 'Failed: latest backup is %s old (limit 7 days). Run a backup first, or pass --skip-backup-check.\n' "$(format_age "$age")" >&2
      return 1
    elif [[ "$age" -gt 172800 ]]; then
      printf 'Warning: latest backup is %s.\n' "$(format_age "$age")"
    fi
  else
    printf 'Warning: could not read the backup timestamp from "%s"; backup age NOT verified.\n' "$latest_backup"
  fi
}

# Join the remaining arguments with the first argument as the separator.
join_by() {
  local sep="$1"
  shift
  local out=""
  local item
  for item in "$@"; do
    out+="${out:+$sep}$item"
  done
  printf '%s' "$out"
}

# Turn a duration in seconds into a compact human age such as "6h ago".
format_age() {
  local seconds="$1"

  if [[ "$seconds" -lt 0 ]]; then
    printf 'in the future'
  elif [[ "$seconds" -lt 3600 ]]; then
    printf '%dm ago' "$((seconds / 60))"
  elif [[ "$seconds" -lt 86400 ]]; then
    printf '%dh ago' "$((seconds / 3600))"
  else
    printf '%dd ago' "$((seconds / 86400))"
  fi
}

# Count lines emitted by a command, swallowing non-zero exits (npm/mas/uv often
# exit non-zero when there is something outdated). Prints a single integer.
count_lines() {
  local output
  output=$("$@" 2>/dev/null) || true
  if [[ -z "$output" ]]; then
    printf '0'
  else
    printf '%s' "$output" | grep -c .
  fi
}

# Start `softwareupdate -l` in the background (it is the slowest pre-flight scan).
# The python plan waits on su.done; capture_softwareupdate_list joins it.
start_softwareupdate_scan() {
  command -v softwareupdate >/dev/null 2>&1 || return 0
  [[ -n "$softwareupdate_pid" ]] && return 0
  ( softwareupdate -l >"$scan_dir/su.txt" 2>&1; : >"$scan_dir/su.done" ) &
  softwareupdate_pid=$!
}

# Load the scan result once. Call it from the parent shell (not inside $(...)) the
# first time, so the cache survives; later subshell calls just reuse the variable.
capture_softwareupdate_list() {
  if [[ "$softwareupdate_list_captured" == true ]]; then
    return 0
  fi
  softwareupdate_list_captured=true
  if [[ -n "$softwareupdate_pid" ]]; then
    wait "$softwareupdate_pid" 2>/dev/null
    softwareupdate_list_output=$(cat "$scan_dir/su.txt" 2>/dev/null) || true
  fi
}

macos_update_count() {
  capture_softwareupdate_list
  if [[ -z "$softwareupdate_list_output" ]]; then
    printf '0'
  else
    printf '%s' "$softwareupdate_list_output" | grep -c '\* Label:'
  fi
}

# Count only genuine macOS *system* updates, i.e. entries whose Title starts with
# "macOS". `softwareupdate -l` also lists XProtect config data, Safari and the
# Command Line Tools; those do not move the system libraries Homebrew formulae
# link against, so they must not trigger the install-macOS-first advice.
# macos_update_count() stays the all-updates count used by the pending summary.
macos_system_update_lines() {
  capture_softwareupdate_list
  if [[ -z "$softwareupdate_list_output" ]]; then
    return 0
  fi
  printf '%s' "$softwareupdate_list_output" | grep 'Title:[[:space:]]*macOS' || true
}

macos_system_update_count() {
  local lines
  lines=$(macos_system_update_lines)
  if [[ -z "$lines" ]]; then
    printf '0'
  else
    printf '%s' "$lines" | grep -c .
  fi
}

# When a macOS update is pending, recommend installing it first and rebooting
# before Homebrew and the rest. A macOS update can move the Command Line Tools and
# system libraries that Homebrew formulae link against, so brewing on the fresh
# system avoids mismatches. This is advisory only: the run still does brew first if
# the user proceeds. Takes the Time Machine backup line so the reminder is concrete.
print_macos_order_advice() {
  local tm_status="$1"
  local count restart_note=""

  if ! command -v softwareupdate >/dev/null 2>&1; then
    return 0
  fi

  capture_softwareupdate_list
  count=$(macos_system_update_count)
  if [[ "$count" -eq 0 ]]; then
    return 0
  fi

  if macos_system_update_lines | grep -iq 'restart'; then
    restart_note=" (it needs a restart)"
  fi

  note ""
  note "Recommended order: a macOS update is pending${restart_note}. It is cleaner to install"
  note "macOS first, reboot, then re-run update-mac for Homebrew and everything else — a macOS"
  note "update can change the Command Line Tools and system libraries that Homebrew links against,"
  note "so upgrading brew on the fresh system avoids mismatches."
  note "Back up with Time Machine before the macOS update. Last backup: ${tm_status}."
  # Say what this run will actually do. The run order is deliberately unchanged
  # (Homebrew first, macOS last), so without this the advice contradicts the very
  # run that prints it — and with --yes there is no prompt at which to act on it.
  if [[ "$assume_yes" == true ]]; then
    note "Note: --yes is set, so this run will NOT stop — it updates Homebrew first, then macOS."
    note "Re-run without --yes if you want to follow the order above."
  else
    if [[ "$classic_prompts" == true ]]; then
      note "This run still updates Homebrew first; press Ctrl-C now to do macOS first instead."
    else
      note "To follow that order, tick only macOS on the selection screen, then re-run update-mac."
    fi
  fi
}

# Render the upgrade plan as a table (one row per outdated package, risky ones first)
# and write a per-tool summary to $scan_dir/summary.tsv for the selection screen.
# Every collector (brew, npm, uv, mas, mise, rustup, softwareupdate) runs concurrently
# in an inline python3 program, so update-mac stays a single portable file (it is meant
# to be copied to ~/bin). All checks are local/read-only: no CVE lookups. Returns
# non-zero if python3 is missing or the program fails, so the caller can fall back to
# the counts line.
print_upgrade_plan() {
  local rc=0

  # On a Mac without the Command Line Tools, /usr/bin/python3 is a shim that exists
  # but fails (or pops an install dialog), so probe it rather than trusting `command -v`.
  if ! command -v python3 >/dev/null 2>&1 || ! python3 -c '' >/dev/null 2>&1; then
    note "(python3 unavailable; showing plain counts instead of the upgrade plan.)"
    capture_softwareupdate_list
    return 1
  fi

  SCAN_DIR="$scan_dir" CUR_VERSION="$(sw_vers -productVersion 2>/dev/null)" \
    SU_EXPECTED="$([[ -n "$softwareupdate_pid" ]] && echo 1 || echo 0)" \
    PLAN_VERBOSE="$verbose" python3 - <<'PY' || rc=$?
import json
import os
import re
import shutil
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor

SCAN_DIR = os.environ["SCAN_DIR"]
CUR_VERSION = os.environ.get("CUR_VERSION", "")
VERBOSE = os.environ.get("PLAN_VERBOSE") == "true"
SU_EXPECTED = os.environ.get("SU_EXPECTED") == "1"

# Same order update-mac runs the tools in.
ORDER = ["Cleanup", "Homebrew", "npm", "Mac App Store", "uv", "pipx", "Volta", "rustup", "mise", "macOS"]
PRERELEASE = re.compile(r"(?i)(beta|canary|nightly|alpha|preview|insider|-rc[-.0-9])")
RANK = {"MAJOR": 0, "restart": 1, "0.x": 2, "pre-release": 3, "pinned": 4}


def run(cmd):
    if not shutil.which(cmd[0]):
        return ""
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    except Exception:
        return ""
    return result.stdout or ""


def parts(version):
    # Integer components of a version, robust to date-versions (25.09) and the
    # comma/hash junk Homebrew puts in some cask versions (1.20.5,5474622945).
    return [int(n) for n in re.findall(r"\d+", version or "")]


def breaking(installed, latest):
    ci, cl = parts(installed), parts(latest)
    if not ci or not cl:
        return None
    if ci[0] != cl[0]:
        return "major"
    if ci[0] == 0 and len(ci) > 1 and len(cl) > 1 and ci[1] != cl[1]:
        return "0.x"
    return None


def short(version):
    # Trim the comma/build junk for display: keep up to the first comma.
    return (version or "").split(",")[0]


def make(tool, name, installed, latest, pinned=False, restart=False, raw=None):
    tags = []
    if pinned:
        tags.append("pinned")
    else:
        kind = breaking(installed, latest)
        if kind:
            tags.append("MAJOR" if kind == "major" else kind)
        # Judge pre-release by the version, not the name (a tool may be called "alpha-x").
        if PRERELEASE.search(latest or ""):
            tags.append("pre-release")
    if restart:
        tags.append("restart")
    return {"tool": tool, "name": name, "raw": raw or name, "installed": installed,
            "latest": latest, "tags": tags}


def rank(item):
    return min([RANK[t] for t in item["tags"]] or [9])


def load_json(raw):
    try:
        return json.loads(raw) if raw.strip() else {}
    except ValueError:
        return {}


def collect_brew():
    if not shutil.which("brew"):
        return None
    data = load_json(run(["brew", "outdated", "--json=v2"]))
    items = []
    for kind, key in (("", "formulae"), (" (cask)", "casks")):
        for it in data.get(key, []):
            installed = (it.get("installed_versions") or [""])[-1]
            items.append(make("Homebrew", (it.get("name") or "?") + kind, installed,
                              it.get("current_version") or "", pinned=bool(it.get("pinned")),
                              raw=it.get("name")))
    return items


def collect_npm():
    if not shutil.which("npm"):
        return None
    data = load_json(run(["npm", "outdated", "-g", "--json"]))
    return [make("npm", name, info.get("current") or "", info.get("latest") or "")
            for name, info in data.items() if isinstance(info, dict)]


def collect_uv():
    if not shutil.which("uv"):
        return None
    items = []
    for line in run(["uv", "tool", "list", "--outdated"]).splitlines():
        m = re.match(r"(\S+)\s+v?(\S+)\s+\[latest:\s*([^\]]+)\]", line.strip())
        if m:
            items.append(make("uv", m.group(1), m.group(2), m.group(3).strip()))
    return items


def collect_mas():
    if not shutil.which("mas"):
        return None
    items = []
    # Mac App Store: "<id>  <name>  (<installed> -> <latest>)"
    for line in run(["mas", "outdated"]).splitlines():
        m = re.match(r"\s*\d+\s+(.+?)\s+\(([^()]*?)\s*->\s*([^()]*?)\)\s*$", line)
        if m:
            items.append(make("Mac App Store", m.group(1), m.group(2), m.group(3)))
    return items


def collect_mise():
    if not shutil.which("mise"):
        return None
    # `mise outdated --json` => {tool: {"current": .., "latest": ..}}
    data = load_json(run(["mise", "outdated", "--json"]))
    return [make("mise", name, info.get("current") or "", info.get("latest") or "")
            for name, info in data.items() if isinstance(info, dict)]


def collect_rustup():
    if not shutil.which("rustup"):
        return None
    items = []
    for line in run(["rustup", "check"]).splitlines():
        m = re.match(r"(\S+)\s+-\s+Update available\s*:\s*(.+?)\s+->\s+(.+)$", line.strip())
        if m:
            items.append(make("rustup", m.group(1), m.group(2).split(" ")[0],
                              m.group(3).split(" ")[0]))
    return items


def collect_macos():
    # softwareupdate -l is started by the shell before this program, because it is the
    # slowest scan; wait for its marker file instead of running it a second time.
    if not SU_EXPECTED:
        return None
    deadline = time.time() + 300
    while not os.path.exists(os.path.join(SCAN_DIR, "su.done")) and time.time() < deadline:
        time.sleep(0.2)
    try:
        text = open(os.path.join(SCAN_DIR, "su.txt")).read()
    except OSError:
        return []
    items = []
    for line in text.splitlines():
        m = re.search(r"Title:\s*([^,]+),\s*Version:\s*([^,]+)", line)
        if m:
            title, version = m.group(1).strip(), m.group(2).strip()
            installed = CUR_VERSION if title.startswith("macOS") else ""
            items.append(make("macOS", title, installed, version,
                              restart="restart" in line.lower()))
    return items


def first(item, *keys):
    for key in keys:
        if item.get(key):
            return item[key]
    return ""


def finding(kind, scope, name, msg, fix):
    clean = lambda t: str(t).replace("\t", " ").replace("\n", " ")
    return {"kind": kind, "scope": clean(scope), "name": clean(name), "msg": clean(msg), "fix": clean(fix)}


def collect_health():
    """Things that no longer work or are on the way out. Read-only; reported, and only the
    Volta 'broken package' kind can be fixed by update-mac (Cleanup entry)."""
    findings = []
    pkgs = []  # (name, version) of global npm packages, for the deprecation check

    # Volta global packages whose files/link target are gone: every update of them fails.
    volta_home = os.environ.get("VOLTA_HOME") or os.path.expanduser("~/.volta")
    udir = os.path.join(volta_home, "tools", "user", "packages")
    if os.path.isdir(udir):
        for root, _, files in os.walk(udir):
            for fname in files:
                if not fname.endswith(".json"):
                    continue
                try:
                    with open(os.path.join(root, fname)) as fh:
                        meta = json.load(fh)
                except (OSError, ValueError):
                    continue
                name, version = meta.get("name") or "", meta.get("version") or ""
                if not name:
                    continue
                manifest = os.path.join(volta_home, "tools", "image", "packages", name,
                                        "lib", "node_modules", name, "package.json")
                if os.path.exists(manifest):
                    pkgs.append((name, version))
                else:
                    findings.append(finding("volta-dangling", "Volta", name,
                                            "package files or link target missing",
                                            "volta uninstall " + name))
    elif shutil.which("npm"):
        data = load_json(run(["npm", "ls", "-g", "--depth=0", "--json"]))
        for name, info in (data.get("dependencies") or {}).items():
            pkgs.append((name, (info or {}).get("version") or ""))

    # Deprecated global npm packages (registry says so); private/local ones just 404 -> silent.
    if shutil.which("npm") and pkgs:
        def deprecated(pv):
            msg = run(["npm", "view", "%s@%s" % pv, "deprecated"]).strip()
            return pv, msg
        with ThreadPoolExecutor(max_workers=8) as pool:
            for (name, version), msg in pool.map(deprecated, pkgs):
                if msg:
                    findings.append(finding("deprecated", "npm global", "%s@%s" % (name, version),
                                            msg.splitlines()[0][:80], "replace it (see message)"))

    # Homebrew formulae/casks that upstream deprecated or disabled.
    if shutil.which("brew"):
        data = load_json(run(["brew", "info", "--json=v2", "--installed"]))
        for key, label in (("formulae", "formula"), ("casks", "cask")):
            for it in data.get(key, []):
                name = it.get("name") or it.get("token") or "?"
                for flag, why, repl in (
                        ("disabled", "disable_reason",
                         ("disable_replacement_formula", "disable_replacement_cask")),
                        ("deprecated", "deprecation_reason",
                         ("deprecation_replacement_formula", "deprecation_replacement_cask"))):
                    if it.get(flag):
                        new = first(it, *repl)
                        fix = ("switch to " + new) if new else "find a replacement, or brew uninstall " + name
                        findings.append(finding(flag, "Homebrew " + label, name,
                                                "%s: %s" % (flag, it.get(why) or "no reason given"), fix))
                        break

    # Dangling symlinks in the bin dirs tools install into.
    for d in ("/opt/homebrew/bin", "/usr/local/bin", os.path.expanduser("~/.local/bin")):
        try:
            entries = list(os.scandir(d))
        except OSError:
            continue
        for e in entries:
            if e.is_symlink() and not os.path.exists(e.path):
                findings.append(finding("broken-link", d, e.name,
                                        "-> %s (missing)" % os.readlink(e.path), "rm " + e.path))
    return findings


COLLECTORS = {
    "Homebrew": collect_brew, "npm": collect_npm, "Mac App Store": collect_mas,
    "uv": collect_uv, "rustup": collect_rustup, "mise": collect_mise, "macOS": collect_macos,
}


def print_table(headers, rows, bold_col=None):
    widths = [max(len(r[i]) for r in rows + [headers]) for i in range(len(headers))]
    print("  " + "  ".join(h.ljust(w) for h, w in zip(headers, widths)))
    print("  " + "  ".join("-" * w for w in widths))
    for r in rows:
        cells = [c.ljust(w) for c, w in zip(r, widths)]
        if bold_col is not None and sys.stdout.isatty() and "MAJOR" in r[bold_col]:
            cells[bold_col] = "\033[1;31m" + cells[bold_col] + "\033[0m"
        print("  " + "  ".join(cells).rstrip())


def main():
    results = {}
    findings = []
    with ThreadPoolExecutor(max_workers=len(COLLECTORS) + 1) as pool:
        futures = {tool: pool.submit(fn) for tool, fn in COLLECTORS.items()}
        health = pool.submit(collect_health)
        for tool, future in futures.items():
            try:
                results[tool] = future.result()
            except Exception as exc:
                sys.stderr.write("update-mac: %s scan failed: %s\n" % (tool, exc))
                results[tool] = []
        try:
            findings = health.result()
        except Exception as exc:
            sys.stderr.write("update-mac: health scan failed: %s\n" % exc)

    rows, summary, outdated = [], [], []
    for tool in ORDER:
        items = results.get(tool)
        if items is None:
            continue
        items.sort(key=lambda it: (rank(it), it["name"].lower()))
        risky = [it for it in items if it["tags"]]
        routine = [it for it in items if not it["tags"]]
        for it in (items if VERBOSE else risky):
            rows.append((tool, it["name"][:42], short(it["installed"]), short(it["latest"]),
                         ", ".join(it["tags"])))
        if routine and not VERBOSE:
            rows.append((tool, "(+%d routine, same major; --verbose lists them)" % len(routine),
                         "", "", ""))
        for it in items:
            outdated.append("\t".join([tool, it["raw"], it["installed"], it["latest"],
                                       ",".join(it["tags"])]))
        tags = [t for it in items for t in it["tags"]]
        summary.append("\t".join([tool, str(len(items)), str(tags.count("MAJOR")),
                                  str(tags.count("pre-release")), str(tags.count("pinned")),
                                  str(tags.count("restart")), ""]))

    if findings:
        fixable = [f for f in findings if f["kind"] == "volta-dangling"]
        warn = [f for f in findings if f["kind"] in ("deprecated", "disabled")]
        links = [f for f in findings if f["kind"] == "broken-link"]
        extra = "%d deprecated/disabled, %d broken link(s)" % (len(warn), len(links))
        summary.insert(0, "\t".join(["Cleanup", str(len(fixable)), "0", "0", "0", "0", extra]))

    # Data files for the shell (selection screen, held-back majors, cleanup).
    for name, lines in (("summary.tsv", summary), ("outdated.tsv", outdated),
                        ("findings.tsv", ["\t".join([f["kind"], f["scope"], f["name"], f["msg"], f["fix"]])
                                          for f in findings])):
        with open(os.path.join(SCAN_DIR, name), "w") as fh:
            fh.write("\n".join(lines) + ("\n" if lines else ""))

    if rows:
        print("Upgrade plan (risky first):")
        print_table(("Tool", "Package", "Installed", "Latest", "Risk"), rows, bold_col=4)
    else:
        print("Upgrade plan: nothing pending.")

    if findings:
        print("\nNeeds attention (%d) - things that no longer work or are on the way out:" % len(findings))
        order = {"volta-dangling": 0, "disabled": 1, "deprecated": 2, "broken-link": 3}
        findings.sort(key=lambda f: (order.get(f["kind"], 9), f["scope"], f["name"]))
        table = []
        for f in findings:
            if f["kind"] == "broken-link" and not VERBOSE:
                same = [g for g in findings if g["kind"] == "broken-link" and g["scope"] == f["scope"]]
                if len(same) > 3:
                    if f is same[0]:
                        names = ", ".join(g["name"] for g in same)
                        table.append((f["scope"], "%d dead symlinks" % len(same), names[:60] + ("..." if len(names) > 60 else ""),
                                      "find %s -type l ! -exec test -e {} \\; -print   (--verbose lists each)" % f["scope"]))
                    continue
            table.append((f["scope"], f["name"], f["msg"][:80], f["fix"]))
        print_table(("Where", "Item", "Problem", "Suggested fix"), table)
        if any(f["kind"] == "volta-dangling" for f in findings):
            print("  Tick 'Cleanup' on the selection screen to remove the broken Volta packages.")
    return 0

try:
    sys.exit(main())
except Exception as exc:
    sys.stderr.write("update-mac: upgrade plan failed: %s\n" % exc)
    sys.exit(1)
PY

  capture_softwareupdate_list
  return "$rc"
}

# Sets di_* from the tool's row in $scan_dir/summary.tsv. di_count stays "?" when the
# tool has no row (no cheap outdated check, e.g. pipx and Volta).
domain_info() {
  local line
  di_count="?"
  di_major=0
  di_pre=0
  di_pinned=0
  di_restart=0
  di_extra=""
  line=$(awk -F'\t' -v l="$1" '$1==l' "$scan_dir/summary.tsv" 2>/dev/null)
  if [[ -n "$line" ]]; then
    IFS=$'\t' read -r _ di_count di_major di_pre di_pinned di_restart di_extra <<<"$line"
  fi
}

# One-line description of a tool for the summary table and the selection screen.
domain_text() {
  local label="$1" detail=""

  domain_info "$label"
  if [[ "$label" == Cleanup ]]; then
    printf '%s broken Volta package(s) removable%s' "$di_count" "${di_extra:+ ($di_extra)}"
    return 0
  fi
  if [[ "$di_count" == "?" ]]; then
    printf 'no outdated check'
    return 0
  fi
  if [[ "$di_major" -gt 0 ]]; then
    if [[ "$include_major" == true ]]; then
      detail="${di_major} MAJOR included"
    else
      detail="${di_major} MAJOR held back"
    fi
  fi
  [[ "$di_restart" -gt 0 ]] && detail="${detail}${detail:+, }needs restart"
  [[ "$di_pre" -gt 0 ]] && detail="${detail}${detail:+, }${di_pre} pre-release"
  [[ "$di_pinned" -gt 0 ]] && detail="${detail}${detail:+, }${di_pinned} pinned"
  printf '%s outdated%s' "$di_count" "${detail:+ ($detail)}"
}

# Should domain index $1 appear in the summary/selection? (tool installed; macOS not
# skipped; Cleanup only when something is removable)
domain_listed() {
  local i="$1"

  command -v "${domain_cmds[$i]}" >/dev/null 2>&1 || return 1
  case "${domain_labels[$i]}" in
    macOS)
      [[ "$skip_macos" == true ]] && return 1
      ;;
    Cleanup)
      domain_info Cleanup
      [[ "$di_count" != "?" && "$di_count" -gt 0 ]] || return 1
      ;;
  esac
  return 0
}

# Plain summary table (used by --dry-run, --yes and --ask, where there is no selection screen).
print_summary_table() {
  local i

  log "Summary"
  printf '  %-14s %s\n' "Tool" "Status"
  for ((i = 0; i < ${#domain_labels[@]}; i++)); do
    domain_listed "$i" || continue
    printf '  %-14s %s\n' "${domain_labels[$i]}" "$(domain_text "${domain_labels[$i]}")"
  done
}

# Plan data helpers. outdated.tsv rows: tool, name, installed, latest, tags (comma list).
# outdated_names: what to upgrade now (pinned never; MAJOR only with include_major).
outdated_names() {
  awk -F'\t' -v t="$1" -v inc="$include_major" \
    '$1==t && $5 !~ /pinned/ && (inc=="true" || $5 !~ /MAJOR/) {print $2}' \
    "$scan_dir/outdated.tsv" 2>/dev/null
}

# held_back_names: MAJOR jumps being left alone this run.
held_back_names() {
  [[ "$include_major" == true ]] && return 0
  awk -F'\t' -v t="$1" '$1==t && $5 !~ /pinned/ && $5 ~ /MAJOR/ {print $2}' \
    "$scan_dir/outdated.tsv" 2>/dev/null
}

# Exit 0 if $1 is a Volta package the health scan found broken.
is_dangling() {
  awk -F'\t' -v n="$1" '$1=="volta-dangling" && $3==n {f=1} END{exit !f}' \
    "$scan_dir/findings.tsv" 2>/dev/null
}

# Keyboard checklist (pure bash 3.2, no dependencies). Enter is the single approval:
# every ticked tool is then run, one step at a time, without further prompts.
# Sets selection_mode/selected_labels; exits if the user quits or selects nothing.
tui_labels=()
tui_marks=()
tui_cursor=0

tui_draw() {
  local i mark total="${#tui_labels[@]}" count=0

  [[ "$1" == redraw ]] && printf '\033[%dA' "$((total + 2))" >/dev/tty
  printf '\r\033[K  Select what to update   ↑/↓ j/k move · space toggle · a all · n none · m majors · enter RUN · q quit\n' >/dev/tty
  for ((i = 0; i < total; i++)); do
    mark=' '
    if [[ "${tui_marks[$i]}" -eq 1 ]]; then
      mark=x
      count=$((count + 1))
    fi
    if [[ "$i" -eq "$tui_cursor" ]]; then
      printf '\r\033[K\033[7m> [%s] %-14s %s\033[0m\n' "$mark" "${tui_labels[$i]}" "$(domain_text "${tui_labels[$i]}")" >/dev/tty
    else
      printf '\r\033[K  [%s] %-14s %s\n' "$mark" "${tui_labels[$i]}" "$(domain_text "${tui_labels[$i]}")" >/dev/tty
    fi
  done
  printf '\r\033[K  %d selected   -   major version jumps: %s (m toggles)\n' "$count" \
    "$([[ "$include_major" == true ]] && echo INCLUDED || echo held back)" >/dev/tty
}

choose_domains() {
  local i mark key rest total j
  local chosen=""

  for ((i = 0; i < ${#domain_labels[@]}; i++)); do
    domain_listed "$i" || continue
    domain_info "${domain_labels[$i]}"
    # Pre-tick a tool only when it has something to do without a major jump (unknown
    # counts, e.g. pipx/Volta, are ticked). An OS update or a removal is never pre-ticked:
    # those are deliberate choices.
    mark=1
    if [[ "$di_count" != "?" ]]; then
      mark=0
      [[ $((di_count - di_major)) -gt 0 ]] && mark=1
    fi
    [[ "${domain_labels[$i]}" == macOS || "${domain_labels[$i]}" == Cleanup ]] && mark=0
    tui_labels+=("${domain_labels[$i]}")
    tui_marks+=("$mark")
  done

  total=${#tui_labels[@]}
  if [[ "$total" -eq 0 ]]; then
    note "No supported tools found."
    exit 0
  fi

  log "Choose what to update"
  tui_draw first
  while true; do
    IFS= read -rsn1 key </dev/tty || exit 2
    case "$key" in
      $'\033')
        rest=""
        read -rsn2 -t 1 rest </dev/tty || rest=""
        case "$rest" in
          '[A') [[ "$tui_cursor" -gt 0 ]] && tui_cursor=$((tui_cursor - 1)) ;;
          '[B') [[ "$tui_cursor" -lt $((total - 1)) ]] && tui_cursor=$((tui_cursor + 1)) ;;
        esac
        ;;
      k) [[ "$tui_cursor" -gt 0 ]] && tui_cursor=$((tui_cursor - 1)) ;;
      j) [[ "$tui_cursor" -lt $((total - 1)) ]] && tui_cursor=$((tui_cursor + 1)) ;;
      ' ') tui_marks[tui_cursor]=$((1 - tui_marks[tui_cursor])) ;;
      a) for ((j = 0; j < total; j++)); do tui_marks[j]=1; done ;;
      n) for ((j = 0; j < total; j++)); do tui_marks[j]=0; done ;;
      m) [[ "$include_major" == true ]] && include_major=false || include_major=true ;;
      q)
        printf '\nQuit requested. Nothing was changed.\n'
        exit 130
        ;;
      '') break ;;
    esac
    tui_draw redraw
  done

  for ((i = 0; i < total; i++)); do
    [[ "${tui_marks[$i]}" -eq 1 ]] && chosen="${chosen}${chosen:+, }${tui_labels[$i]}" \
      && selected_labels="${selected_labels}${tui_labels[$i]}|"
  done
  if [[ -z "$chosen" ]]; then
    printf '\nNothing selected. Nothing was changed.\n'
    exit 0
  fi
  selected_labels="|${selected_labels}"
  selection_mode=true
  printf '\nApproved once: %s\nRunning one step at a time, no further prompts.\n' "$chosen"
}

print_preflight_summary() {
  local macos_version macos_build host disk_free
  local tm_line="unknown (grant Full Disk Access)"
  local latest_backup backup_stamp backup_epoch now_epoch

  log "Pre-flight summary"

  # Kick the slow macOS scan off now; it runs while the checks below execute.
  start_softwareupdate_scan

  macos_version=$(sw_vers -productVersion 2>/dev/null || printf '?')
  macos_build=$(sw_vers -buildVersion 2>/dev/null || printf '?')
  host=$(scutil --get LocalHostName 2>/dev/null || hostname 2>/dev/null || printf '?')
  disk_free=$(df -h / 2>/dev/null | awk 'NR==2 {print $4}')
  [[ -z "$disk_free" ]] && disk_free='?'

  if command -v tmutil >/dev/null 2>&1 && latest_backup=$(tmutil latestbackup 2>/dev/null); then
    backup_stamp=$(basename "$latest_backup" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}' | tail -n1)
    if [[ -n "$backup_stamp" ]] && backup_epoch=$(date -j -f '%Y-%m-%d-%H%M%S' "$backup_stamp" '+%s' 2>/dev/null); then
      now_epoch=$(date '+%s')
      tm_line="$backup_stamp ($(format_age "$((now_epoch - backup_epoch))"))"
    elif [[ -n "$latest_backup" ]]; then
      tm_line="$latest_backup"
    fi
  fi

  printf 'Host %s • macOS %s (%s) • disk free %s • TM backup %s\n' \
    "$host" "$macos_version" "$macos_build" "$disk_free" "$tm_line"

  # Toolchain line: Homebrew builds against these, and a stale CLT after a macOS
  # or Xcode update is the classic cause of "brew install" build failures.
  local xcode_ver clt_ver
  xcode_ver=$(xcodebuild -version 2>/dev/null | awk 'NR==1{v=$2} NR==2{b=$3} END{if(v) printf "%s (%s)", v, b}')
  clt_ver=$(pkgutil --pkg-info=com.apple.pkg.CLTools_Executables 2>/dev/null | awk '/^version:/{print $2}')
  printf 'Toolchain: Xcode %s • CLT %s • arch %s\n' "${xcode_ver:-none}" "${clt_ver:-none}" "$(uname -m)"

  # Prefer the grouped, risk-annotated plan. Fall back to a compact counts line
  # only if python3 is unavailable.
  if ! print_upgrade_plan; then
    local parts=()
    capture_softwareupdate_list
    command -v brew >/dev/null 2>&1 && parts+=("brew $(count_lines brew outdated --quiet)")
    command -v npm >/dev/null 2>&1 && parts+=("npm $(count_lines npm outdated -g --depth=0 --parseable)")
    command -v mas >/dev/null 2>&1 && parts+=("mas $(count_lines mas outdated)")
    command -v mise >/dev/null 2>&1 && parts+=("mise $(mise outdated --json 2>/dev/null | grep -c '"current"')")
    command -v uv >/dev/null 2>&1 && parts+=("uv $(count_lines uv tool list --outdated)")
    command -v softwareupdate >/dev/null 2>&1 && parts+=("macOS $(macos_update_count)")

    if [[ "${#parts[@]}" -gt 0 ]]; then
      printf 'Pending: %s\n' "$(join_by '  ' "${parts[@]}")"
      note "(brew count is from last-known data; the run refreshes it first.)"
    fi
  fi

  print_macos_order_advice "$tm_line"

  local flags=()
  [[ "$dry_run" == true ]] && flags+=("dry-run")
  [[ "$use_greedy_casks" == true ]] && flags+=("greedy-casks")
  [[ "$assume_yes" == true ]] && flags+=("yes")
  [[ "$skip_backup_check" == true ]] && flags+=("skip-backup-check")
  if [[ "${#flags[@]}" -gt 0 ]]; then
    printf 'Active flags: %s\n' "${flags[*]}"
  fi
}

# Install pending macOS updates by explicit label, leaving out any macOS entry whose
# major version differs from the running one (a full OS upgrade is never installed
# implicitly; `softwareupdate -i -a` would take it). Needs root, so sudo is used.
# $1 = current major macOS version.
install_macos_updates() {
  local cur_major="$1"
  local labels=()
  local label

  # Entries look like: "* Label: <label>" then "\tTitle: <title>, Version: <v>, ...".
  while IFS= read -r label; do
    [[ -n "$label" ]] && labels+=("$label")
  done < <(printf '%s\n' "$softwareupdate_list_output" | awk -v cur="$cur_major" '
    /^[[:space:]]*\* Label:/ { if (lbl != "" && !skip) print lbl
                               lbl = $0; sub(/^[[:space:]]*\* Label:[[:space:]]*/, "", lbl); skip = 0; next }
    /Title:[[:space:]]*macOS/ { if (match($0, /Version:[[:space:]]*[0-9]+/)) {
                                  v = substr($0, RSTART, RLENGTH); sub(/[^0-9]*/, "", v)
                                  if (v != cur) skip = 1 } }
    END { if (lbl != "" && !skip) print lbl }')

  if [[ "${#labels[@]}" -eq 0 ]]; then
    note "No installable macOS updates (major upgrades are excluded; install those by hand)."
    return 0
  fi
  run_step "macOS software updates (${#labels[@]})" sudo softwareupdate -i "${labels[@]}"
}

# Upgrade global npm packages one at a time, so a single broken package cannot abort the
# rest, and list what failed. Volta manages globals here (`npm update -g` fights it and
# breaks on local-path packages), so use `volta install <pkg>@latest`; plain npm otherwise.
# Major jumps are held back unless include_major.
update_npm_globals() {
  local name pkgs=() held=() failed=()

  if [[ ! -f "$scan_dir/summary.tsv" ]]; then
    if command -v volta >/dev/null 2>&1; then
      note "No upgrade plan (python3 missing) and Volta manages the globals: use 'volta install <pkg>' by hand."
    else
      run_step "npm global package updates" npm update -g
    fi
    return 0
  fi

  while IFS= read -r name; do [[ -n "$name" ]] && pkgs+=("$name"); done < <(outdated_names npm)
  while IFS= read -r name; do [[ -n "$name" ]] && held+=("$name"); done < <(held_back_names npm)

  if [[ "${#pkgs[@]}" -gt 0 ]]; then
    for name in "${pkgs[@]}"; do
      if [[ "$name" == npm ]] && command -v volta >/dev/null 2>&1; then
        note "Skipping npm itself: it ships with Node and is handled by the Volta step."
      elif is_dangling "$name"; then
        note "Skipping $name: broken Volta package (tick Cleanup to remove it)."
      elif command -v volta >/dev/null 2>&1; then
        run_step "Volta install $name@latest" volta install "$name@latest" || failed+=("$name")
      else
        run_step "npm install -g $name@latest" npm install -g "$name@latest" || failed+=("$name")
      fi
    done
  else
    note "No global npm packages to upgrade."
  fi
  [[ "${#held[@]}" -gt 0 ]] && note "Held back (major jump): $(join_by ', ' "${held[@]}"). Re-run with --major (or press m) to include."
  [[ "${#failed[@]}" -gt 0 ]] && note "Failed packages: $(join_by ', ' "${failed[@]}")"
  return 0
}

# Homebrew upgrade that leaves major jumps alone: when the plan found some, upgrade only
# the other planned packages by name; otherwise a plain `brew upgrade` as before.
brew_upgrade_step() {
  local name names=() held=()

  if [[ -f "$scan_dir/summary.tsv" && "$include_major" != true ]]; then
    while IFS= read -r name; do [[ -n "$name" ]] && held+=("$name"); done < <(held_back_names Homebrew)
    if [[ "${#held[@]}" -gt 0 ]]; then
      while IFS= read -r name; do [[ -n "$name" ]] && names+=("$name"); done < <(outdated_names Homebrew)
      note "Holding back major jump(s): $(join_by ', ' "${held[@]}"). Re-run with --major (or press m) to include."
      if [[ "${#names[@]}" -gt 0 ]]; then
        run_step "Homebrew upgrade (without major jumps)" brew upgrade "${names[@]}"
      else
        note "Nothing else to upgrade."
      fi
      return 0
    fi
  fi
  run_step "Homebrew upgrade formulae and standard casks" brew upgrade
}

# Run mise from $HOME so the *global* config is used regardless of the cwd, without
# a login shell (`bash -l` would source profile files and can hang or print noise).
mise_in_home() {
  (cd "$HOME" && mise "$@")
}

# "node@24" (stay on the installed major) or plain "node" when major jumps are included.
volta_spec() {
  local major

  if [[ "$include_major" == true ]]; then
    printf '%s' "$1"
    return 0
  fi
  major=$("$1" --version 2>/dev/null | grep -oE '[0-9]+' | head -n1)
  printf '%s' "${major:+$1@$major}"
  [[ -n "$major" ]] || printf '%s' "$1"
}

update_volta_defaults() {
  preview_step "Volta managed tools" volta list all

  local steps=()
  volta which node >/dev/null 2>&1 && steps+=("default Node")
  volta which npm >/dev/null 2>&1 && steps+=("default npm")
  command -v yarn >/dev/null 2>&1 && volta which yarn >/dev/null 2>&1 && steps+=("default Yarn")
  command -v pnpm >/dev/null 2>&1 && volta which pnpm >/dev/null 2>&1 && steps+=("default pnpm")

  if [[ "${#steps[@]}" -eq 0 ]]; then
    note "Volta is installed, but no managed default tools were detected. If you want to move a default runtime forward, run: volta install node npm"
    return
  fi

  if begin_domain "Volta" "$(join_by ', ' "${steps[@]}")"; then
    volta which node >/dev/null 2>&1 && run_step "Volta default Node" volta install "$(volta_spec node)"
    volta which npm >/dev/null 2>&1 && run_step "Volta default npm" volta install "$(volta_spec npm)"
    command -v yarn >/dev/null 2>&1 && volta which yarn >/dev/null 2>&1 && run_step "Volta default Yarn" volta install "$(volta_spec yarn)"
    command -v pnpm >/dev/null 2>&1 && volta which pnpm >/dev/null 2>&1 && run_step "Volta default pnpm" volta install "$(volta_spec pnpm)"
  fi
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -n|--dry-run)
      dry_run=true
      ;;
    --greedy-casks|--greedy)
      use_greedy_casks=true
      ;;
    -y|--yes)
      assume_yes=true
      yes_flag=true
      ;;
    --with-macos)
      with_macos=true
      ;;
    --skip-backup-check)
      skip_backup_check=true
      ;;
    --skip-macos)
      skip_macos=true
      ;;
    --ask)
      classic_prompts=true
      ;;
    --major)
      include_major=true
      ;;
    -v|--verbose)
      verbose=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

# Dry-run mutates nothing, so it overrides --yes.
if [[ "$dry_run" == true ]]; then
  assume_yes=false
fi

ensure_prompt_available

print_preflight_summary

if [[ "$dry_run" == true ]]; then
  log "Time Machine safety gate"
  printf 'Skipped: --dry-run mutates nothing.\n'
elif [[ "$skip_backup_check" == true ]]; then
  log "Time Machine safety gate"
  printf 'Skipped: --skip-backup-check was passed.\n'
elif ! require_time_machine_backup; then
  exit 1
fi

# One approval for the whole run: pick tools on the selection screen (interactive), or
# just show the summary table in --dry-run / --yes / --ask.
if [[ "$dry_run" != true && "$assume_yes" != true && "$classic_prompts" != true ]]; then
  choose_domains
else
  print_summary_table
fi

# Cleanup: remove Volta packages the health scan found broken (they fail every update).
# Never run by --yes: removal is always a deliberate choice (selection screen or a prompt).
cleanup_names=()
while IFS= read -r cleanup_name; do
  [[ -n "$cleanup_name" ]] && cleanup_names+=("$cleanup_name")
done < <(awk -F'\t' '$1=="volta-dangling" {print $3}' "$scan_dir/findings.tsv" 2>/dev/null)
if [[ "${#cleanup_names[@]}" -gt 0 ]]; then
  if [[ "$assume_yes" == true && "$selection_mode" != true ]]; then
    note "Cleanup: ${#cleanup_names[@]} broken Volta package(s) found ($(join_by ', ' "${cleanup_names[@]}")); --yes never removes anything. Use the selection screen, or: volta uninstall <name>"
  elif begin_domain "Cleanup" "remove broken Volta packages: $(join_by ', ' "${cleanup_names[@]}")"; then
    for cleanup_name in "${cleanup_names[@]}"; do
      run_step "Volta uninstall $cleanup_name" volta uninstall "$cleanup_name"
    done
  fi
fi

# Per-tool previews are intentionally minimal: the pre-flight upgrade plan already
# lists what brew/npm/uv would change. Only previews the plan does not cover are kept.
if command -v brew >/dev/null 2>&1; then
  if [[ "$use_greedy_casks" == true ]]; then
    preview_step "Homebrew outdated greedy casks (not in the plan above)" brew outdated --cask --greedy --verbose
    if begin_domain "Homebrew" "update, upgrade, greedy cask upgrade, cleanup, doctor"; then
      # Upgrading on stale metadata is worse than not upgrading: stop if update fails.
      if run_step "Homebrew update" brew update; then
        brew_upgrade_step
        run_step "Homebrew greedy cask upgrade" brew upgrade --cask --greedy
        run_step "Homebrew cleanup" brew cleanup
      else
        note "Skipping Homebrew upgrade/cleanup because the update step failed."
      fi
      run_info "Homebrew doctor" brew doctor
    fi
  else
    hint "Skipping greedy cask upgrades. Use --greedy-casks if you want to force auto-updating casks."
    if begin_domain "Homebrew" "update, upgrade, cleanup, doctor"; then
      if run_step "Homebrew update" brew update; then
        brew_upgrade_step
        run_step "Homebrew cleanup" brew cleanup
      else
        note "Skipping Homebrew upgrade/cleanup because the update step failed."
      fi
      run_info "Homebrew doctor" brew doctor
    fi
  fi
else
  missing_tool "brew" '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' "https://brew.sh/"
fi

if command -v npm >/dev/null 2>&1; then
  if begin_domain "npm" "global package upgrades (one by one), cache verify"; then
    update_npm_globals
    run_step "npm cache verify" npm cache verify
  fi
else
  note 'Not installed: npm. Install Node first, for example with "volta install node" or "brew install node".'
fi

if command -v mas >/dev/null 2>&1; then
  preview_step "Mac App Store outdated apps" mas outdated
  if begin_domain "Mac App Store" "upgrade outdated apps"; then
    run_step "Mac App Store updates" mas upgrade
  fi
else
  missing_tool "mas" "brew install mas" "https://github.com/mas-cli/mas"
fi

if command -v uv >/dev/null 2>&1; then
  # -x: exact process name (a bare `pgrep -f uv` also matches this very command line).
  preview_step "uv processes currently running (cache may be locked by these)" bash -c 'pgrep -lx uv || echo none'
  if begin_domain "uv" "tool upgrades, cache prune"; then
    run_step "uv tool upgrades" uv tool upgrade --all
    run_step "uv cache prune" uv cache prune
  fi
else
  missing_tool "uv" "brew install uv" "https://docs.astral.sh/uv/"
fi

if command -v pipx >/dev/null 2>&1; then
  preview_step "pipx installed packages" pipx list
  hint "pipx does not provide a compact outdated summary here, so the installed package list is shown before upgrades."
  if begin_domain "pipx" "package upgrades, shared library upgrades"; then
    run_step "pipx package upgrades" pipx upgrade-all
    run_step "pipx shared library upgrades" pipx upgrade-shared
  fi
else
  missing_tool "pipx" "brew install pipx && pipx ensurepath" "https://pipx.pypa.io/latest/installation/"
fi

if command -v volta >/dev/null 2>&1; then
  update_volta_defaults
else
  missing_tool "volta" 'curl https://get.volta.sh | bash' "https://docs.volta.sh/guide/getting-started/"
fi

if command -v rustup >/dev/null 2>&1; then
  preview_step "rustup available updates" rustup check
  if begin_domain "rustup" "toolchain updates"; then
    run_step "rustup toolchain updates" rustup update
    run_info "rustup check" rustup check
  fi
else
  missing_tool "rustup" "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh" "https://www.rust-lang.org/tools/install"
fi

if command -v mise >/dev/null 2>&1; then
  preview_step "mise outdated tools" mise_in_home outdated
  preview_step "mise current tools" mise_in_home list
  hint "mise: outdated tools and the current list are shown above before any upgrade."
  if begin_domain "mise" "tool upgrades, cache prune, doctor"; then
    run_step "mise tool upgrades" mise_in_home upgrade
    run_step "mise cache prune" mise_in_home cache prune
    run_info "mise doctor" mise_in_home doctor
  fi
else
  missing_tool "mise" "brew install mise" "https://mise.jdx.dev/getting-started.html"
fi

if command -v softwareupdate >/dev/null 2>&1; then
  capture_softwareupdate_list
  cur_major=""
  log "Available macOS software updates"
  if [[ -n "$softwareupdate_list_output" ]]; then
    # A major jump (e.g. 26 -> 27) is a full OS upgrade, not a routine update.
    cur_major=$(sw_vers -productVersion 2>/dev/null | cut -d. -f1)
    if macos_system_update_lines | grep -oE 'Version:[[:space:]]*[0-9]+' | awk -v c="$cur_major" -F'[: ]+' '$NF!=c{f=1} END{exit !f}'; then
      note "Note: a MAJOR macOS upgrade is listed (current major: ${cur_major:-?}). Do that deliberately, after a backup; use --skip-macos to leave it alone."
    fi
    # The plan above already flags the count and any restart; show just the labels here.
    printf '%s\n' "$softwareupdate_list_output" | grep '\* Label:' || printf 'See the upgrade plan above.\n'
  else
    printf 'No pending changes reported.\n'
  fi
  if [[ "$skip_macos" == true ]]; then
    note "Skipped: --skip-macos was passed."
  elif [[ "$yes_flag" == true && "$with_macos" != true ]]; then
    note "Skipped: --yes does not run the macOS update. Add --with-macos or run softwareupdate -i -a yourself."
  else
    # [A]ll must not approve an OS update: ask again on its own, ignoring assume_yes.
    # --yes + --with-macos is the one explicit non-interactive opt-in.
    saved_assume_yes=$assume_yes
    [[ "$yes_flag" == true ]] || assume_yes=false
    begin_domain "macOS" "install all available software updates (not covered by [A]ll)" && macos_ok=true || macos_ok=false
    assume_yes=$saved_assume_yes
    [[ "$macos_ok" == true ]] && install_macos_updates "$cur_major"
  fi
else
  note "softwareupdate is not available on this machine."
fi

close_domain
print_results_table

if [[ "$dry_run" == true ]]; then
  printf '\nDry run complete. Nothing was changed.\n'
  exit 0
fi

if [[ "$failures" -gt 0 ]]; then
  printf '\nFinished with %s failed step(s).\n' "$failures" >&2
  exit 1
fi

printf '\nAll update steps finished successfully.\n'
