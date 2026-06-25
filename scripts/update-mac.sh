#!/usr/bin/env bash

set -u
set -o pipefail

failures=0
use_greedy_casks=false
assume_yes=false
skip_backup_check=false
dry_run=false

# Captured once by the pre-flight summary and reused by the macOS step so the
# slow `softwareupdate -l` network scan only runs a single time per invocation.
softwareupdate_list_output=""
softwareupdate_list_captured=false

usage() {
  cat <<'EOF'
Usage: update-mac [--dry-run] [--greedy-casks] [--yes] [--skip-backup-check]

Default behavior:
- Prints a pre-flight summary (system status + pending update counts) before touching anything.
- Refuses to upgrade anything unless Time Machine has a latest backup and a visible destination.
- Asks once per tool (Homebrew, npm, ...) with Yes / No / Skip / All / Quit.
- Shows a preview first when the tool has a useful non-mutating check.
- Updates Homebrew without forcing auto-updating casks.

Options:
  -n, --dry-run        Preview every step and mutate nothing. Shows the summary and what each
                       tool would do, then exits. Skips the Time Machine gate (nothing changes).
  --greedy-casks       Force Homebrew to upgrade auto-updating casks too.
  -y, --yes            Run mutating steps without interactive approval.
  --skip-backup-check  Skip the Time Machine safety gate. Use when Terminal lacks
                       Full Disk Access and tmutil latestbackup cannot run.
  -h, --help           Show this help.

At any prompt, choose [A]ll to approve this and every remaining tool without further prompts.
EOF
}

log() {
  printf '\n==> %s\n' "$1"
}

note() {
  printf '%s\n' "$1"
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
  fi
}

preview_step() {
  local label="$1"
  shift
  local output=""
  local status=0

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
  if [[ ! -t 0 || ! -r /dev/tty ]]; then
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
begin_domain() {
  local label="$1"
  local steps="$2"
  local prompt_status=0

  if [[ "$dry_run" == true ]]; then
    log "$label"
    printf '[dry-run] Would run: %s\n' "$steps"
    return 1
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

# Capture `softwareupdate -l` once. The macOS step reuses the result so the slow
# network scan does not run twice in a single invocation.
capture_softwareupdate_list() {
  if [[ "$softwareupdate_list_captured" == true ]]; then
    return 0
  fi
  softwareupdate_list_captured=true
  if command -v softwareupdate >/dev/null 2>&1; then
    softwareupdate_list_output=$(softwareupdate -l 2>&1) || true
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

# Render a grouped, risk-annotated upgrade plan. Uses an inline python3 program so
# update-mac stays a single portable file (it is meant to be copied to ~/bin). All
# checks are local: no network, no CVE lookups. Returns non-zero if python3 is
# missing or the program fails, so the caller can fall back to the counts line.
print_upgrade_plan() {
  if ! command -v python3 >/dev/null 2>&1; then
    return 1
  fi

  capture_softwareupdate_list

  SOFTWAREUPDATE_LIST="$softwareupdate_list_output" python3 - <<'PY'
import json
import os
import re
import shutil
import subprocess
import sys

PRERELEASE = re.compile(r"(?i)(beta|canary|nightly|alpha|preview|insider|-rc[-.0-9])")


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


def collect():
    items = []  # (name, installed, latest, kind, pinned, prerelease)

    brew_raw = run(["brew", "outdated", "--json=v2"])
    if brew_raw.strip():
        try:
            data = json.loads(brew_raw)
        except ValueError:
            data = {}
        for kind, key in (("formula", "formulae"), ("cask", "casks")):
            for it in data.get(key, []):
                installed = (it.get("installed_versions") or [""])[0]
                latest = it.get("current_version") or ""
                name = it.get("name") or "?"
                pre = bool(PRERELEASE.search(name) or PRERELEASE.search(latest))
                items.append((name, installed, latest, kind, bool(it.get("pinned")), pre))

    npm_raw = run(["npm", "outdated", "-g", "--json"])
    if npm_raw.strip():
        try:
            ndata = json.loads(npm_raw)
        except ValueError:
            ndata = {}
        for name, info in ndata.items():
            installed = info.get("current") or ""
            latest = info.get("latest") or ""
            pre = bool(PRERELEASE.search(name) or PRERELEASE.search(latest))
            items.append((name, installed, latest, "npm", False, pre))

    for line in run(["uv", "tool", "list", "--outdated"]).splitlines():
        m = re.match(r"(\S+)\s+v?(\S+)\s+\[latest:\s*([^\]]+)\]", line.strip())
        if m:
            name, installed, latest = m.group(1), m.group(2), m.group(3).strip()
            pre = bool(PRERELEASE.search(name) or PRERELEASE.search(latest))
            items.append((name, installed, latest, "uv", False, pre))

    return items


def macos_info():
    text = os.environ.get("SOFTWAREUPDATE_LIST", "")
    labels = re.findall(r"^\*\s*Label:", text, re.MULTILINE)
    restart = []
    for line in text.splitlines():
        if "Title:" in line and "restart" in line.lower():
            m = re.search(r"Title:\s*([^,]+)", line)
            if m:
                restart.append(m.group(1).strip())
    return len(labels), restart


def main():
    items = collect()
    macos_count, restart_titles = macos_info()

    counts = {}
    for _, _, _, kind, _, _ in items:
        counts[kind] = counts.get(kind, 0) + 1

    head = []
    for kind, label in (("formula", "formulae"), ("cask", "casks"), ("npm", "npm"), ("uv", "uv")):
        if counts.get(kind):
            head.append("%d %s" % (counts[kind], label))
    if macos_count:
        head.append("%d macOS" % macos_count)

    if not head:
        print("Upgrade plan: nothing pending.")
        return 0

    print("Upgrade plan: " + ", ".join(head))

    major = [it for it in items if not it[4] and breaking(it[1], it[2])]
    prerel = [it for it in items if not it[4] and not breaking(it[1], it[2]) and it[5]]
    pinned = [it for it in items if it[4]]

    if major:
        print("  !! major version jump (review release notes):")
        width = max(len(it[0]) for it in major)
        for name, installed, latest, kind, _, pre in major:
            tags = kind if kind in ("cask", "npm", "uv") else ""
            if pre:
                tags = (tags + ", pre-release").lstrip(", ")
            suffix = "   (%s)" % tags if tags else ""
            print("       %-*s  %s -> %s%s" % (width, name, short(installed), short(latest), suffix))

    if restart_titles:
        print("  !! macOS update requires a RESTART: " + "; ".join(restart_titles))

    if prerel:
        print("  ~  pre-release channel (auto-updating beta/canary/nightly):")
        for name, installed, latest, kind, _, _ in prerel:
            print("       %s  %s -> %s" % (name, short(installed), short(latest)))

    if pinned:
        print("     pinned (won't upgrade): " + ", ".join(it[0] for it in pinned))

    routine = [
        it for it in items
        if not it[4] and not breaking(it[1], it[2]) and not it[5]
    ]
    if routine:
        rc = {}
        for _, _, _, kind, _, _ in routine:
            rc[kind] = rc.get(kind, 0) + 1
        summary = ", ".join(
            "%d %s" % (rc[k], lbl)
            for k, lbl in (("formula", "formulae"), ("cask", "casks"), ("npm", "npm"), ("uv", "uv"))
            if rc.get(k)
        )
        print("     routine (same major version): " + summary)

    return 0


try:
    sys.exit(main())
except Exception:
    sys.exit(1)
PY
}

print_preflight_summary() {
  local macos_version macos_build host disk_free
  local tm_line="unknown (grant Full Disk Access)"
  local latest_backup backup_stamp backup_epoch now_epoch

  log "Pre-flight summary"

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

  # Prefer the grouped, risk-annotated plan. Fall back to a compact counts line
  # only if python3 is unavailable.
  if ! print_upgrade_plan; then
    local parts=()
    command -v brew >/dev/null 2>&1 && parts+=("brew $(count_lines brew outdated --quiet)")
    command -v npm >/dev/null 2>&1 && parts+=("npm $(count_lines npm outdated -g --depth=0 --parseable)")
    command -v mas >/dev/null 2>&1 && parts+=("mas $(count_lines mas outdated)")
    command -v uv >/dev/null 2>&1 && parts+=("uv $(count_lines uv tool list --outdated)")
    command -v softwareupdate >/dev/null 2>&1 && parts+=("macOS $(macos_update_count)")

    if [[ "${#parts[@]}" -gt 0 ]]; then
      printf 'Pending: %s\n' "$(join_by '  ' "${parts[@]}")"
      note "(brew count is from last-known data; the run refreshes it first.)"
    fi
  fi

  local flags=()
  [[ "$dry_run" == true ]] && flags+=("dry-run")
  [[ "$use_greedy_casks" == true ]] && flags+=("greedy-casks")
  [[ "$assume_yes" == true ]] && flags+=("yes")
  [[ "$skip_backup_check" == true ]] && flags+=("skip-backup-check")
  if [[ "${#flags[@]}" -gt 0 ]]; then
    printf 'Active flags: %s\n' "${flags[*]}"
  fi
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
    volta which node >/dev/null 2>&1 && run_step "Volta default Node" volta install node
    volta which npm >/dev/null 2>&1 && run_step "Volta default npm" volta install npm
    command -v yarn >/dev/null 2>&1 && volta which yarn >/dev/null 2>&1 && run_step "Volta default Yarn" volta install yarn
    command -v pnpm >/dev/null 2>&1 && volta which pnpm >/dev/null 2>&1 && run_step "Volta default pnpm" volta install pnpm
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
      ;;
    --skip-backup-check)
      skip_backup_check=true
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

# Per-tool previews are intentionally minimal: the pre-flight upgrade plan already
# lists what brew/npm/uv would change. Only previews the plan does not cover are kept.
if command -v brew >/dev/null 2>&1; then
  if [[ "$use_greedy_casks" == true ]]; then
    preview_step "Homebrew outdated greedy casks (not in the plan above)" brew outdated --cask --greedy --verbose
    if begin_domain "Homebrew" "update, upgrade, greedy cask upgrade, cleanup, doctor"; then
      run_step "Homebrew update" brew update
      run_step "Homebrew upgrade formulae and standard casks" brew upgrade
      run_step "Homebrew greedy cask upgrade" brew upgrade --cask --greedy
      run_step "Homebrew cleanup" brew cleanup
      run_step "Homebrew doctor" brew doctor
    fi
  else
    note "Skipping greedy cask upgrades. Use --greedy-casks if you want to force auto-updating casks."
    if begin_domain "Homebrew" "update, upgrade, cleanup, doctor"; then
      run_step "Homebrew update" brew update
      run_step "Homebrew upgrade formulae and standard casks" brew upgrade
      run_step "Homebrew cleanup" brew cleanup
      run_step "Homebrew doctor" brew doctor
    fi
  fi
else
  missing_tool "brew" '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' "https://brew.sh/"
fi

if command -v npm >/dev/null 2>&1; then
  if begin_domain "npm" "global package updates, cache verify"; then
    run_step "npm global package updates" npm update -g
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
  preview_step "uv processes currently running (cache may be locked by these)" bash -c 'pgrep -fl uv || true'
  if begin_domain "uv" "tool upgrades, cache prune"; then
    run_step "uv tool upgrades" uv tool upgrade --all
    run_step "uv cache prune" uv cache prune
  fi
else
  missing_tool "uv" "brew install uv" "https://docs.astral.sh/uv/"
fi

if command -v pipx >/dev/null 2>&1; then
  preview_step "pipx installed packages" pipx list
  note "pipx does not provide a compact outdated summary here, so the installed package list is shown before upgrades."
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
    run_step "rustup check" rustup check
  fi
else
  missing_tool "rustup" "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh" "https://www.rust-lang.org/tools/install"
fi

if command -v mise >/dev/null 2>&1; then
  preview_step "mise current tools" bash -lc 'cd "$HOME" && mise list'
  note "mise does not expose a single generic outdated summary here, so the current tool list is shown before upgrades."
  if begin_domain "mise" "tool upgrades, cache prune, doctor"; then
    run_step "mise tool upgrades" bash -lc 'cd "$HOME" && mise upgrade'
    run_step "mise cache prune" mise cache prune
    run_step "mise doctor" mise doctor
  fi
else
  missing_tool "mise" "brew install mise" "https://mise.jdx.dev/getting-started.html"
fi

if command -v softwareupdate >/dev/null 2>&1; then
  capture_softwareupdate_list
  log "Available macOS software updates"
  if [[ -n "$softwareupdate_list_output" ]]; then
    # The plan above already flags the count and any restart; show just the labels here.
    printf '%s\n' "$softwareupdate_list_output" | grep '\* Label:' || printf 'See the upgrade plan above.\n'
  else
    printf 'No pending changes reported.\n'
  fi
  if begin_domain "macOS" "install all available software updates"; then
    run_step "macOS software updates" softwareupdate -i -a
  fi
else
  note "softwareupdate is not available on this machine."
fi

if [[ "$dry_run" == true ]]; then
  printf '\nDry run complete. Nothing was changed.\n'
  exit 0
fi

if [[ "$failures" -gt 0 ]]; then
  printf '\nFinished with %s failed step(s).\n' "$failures" >&2
  exit 1
fi

printf '\nAll update steps finished successfully.\n'
