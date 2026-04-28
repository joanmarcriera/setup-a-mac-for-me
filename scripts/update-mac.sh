#!/usr/bin/env bash

set -u
set -o pipefail

failures=0
use_greedy_casks=false
assume_yes=false
skip_backup_check=false

usage() {
  cat <<'EOF'
Usage: update-mac [--greedy-casks] [--yes] [--skip-backup-check]

Default behavior:
- Refuses to upgrade anything unless Time Machine has a latest backup and a visible destination.
- Prompts before each mutating step with Yes / No / Skip / Quit.
- Shows a preview first when the tool has a useful non-mutating check.
- Updates Homebrew without forcing auto-updating casks.

Options:
  --greedy-casks       Force Homebrew to upgrade auto-updating casks too.
  -y, --yes            Run mutating steps without interactive approval.
  --skip-backup-check  Skip the Time Machine safety gate. Use when Terminal lacks
                       Full Disk Access and tmutil latestbackup cannot run.
  -h, --help           Show this help.
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
  if [[ "$assume_yes" == false ]] && [[ ! -t 0 || ! -r /dev/tty ]]; then
    printf 'Interactive approval is the default, but no terminal prompt is available. Re-run with --yes to auto-approve mutating steps.\n' >&2
    exit 2
  fi
}

prompt_for_step() {
  local label="$1"
  local reply=""
  local normalized=""

  if [[ "$assume_yes" == true ]]; then
    return 0
  fi

  while true; do
    printf 'Run "%s"? [Y]es/[n]o/[s]kip/[q]uit (default yes): ' "$label" >/dev/tty
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
      q|quit)
        return 3
        ;;
      *)
        printf 'Enter yes, no, skip, or quit.\n' >/dev/tty
        ;;
    esac
  done
}

run_mutating_step() {
  local label="$1"
  shift
  local prompt_status=0

  prompt_for_step "$label"
  prompt_status=$?

  case "$prompt_status" in
    0)
      run_step "$label" "$@"
      ;;
    1)
      printf 'Not run: %s\n' "$label"
      ;;
    2)
      printf 'Skipped: %s\n' "$label"
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

update_volta_defaults() {
  local updated_any=false

  preview_step "Volta managed tools" volta list all

  if volta which node >/dev/null 2>&1; then
    run_mutating_step "Volta default Node" volta install node
    updated_any=true
  fi

  if volta which npm >/dev/null 2>&1; then
    run_mutating_step "Volta default npm" volta install npm
    updated_any=true
  fi

  if command -v yarn >/dev/null 2>&1 && volta which yarn >/dev/null 2>&1; then
    run_mutating_step "Volta default Yarn" volta install yarn
    updated_any=true
  fi

  if command -v pnpm >/dev/null 2>&1 && volta which pnpm >/dev/null 2>&1; then
    run_mutating_step "Volta default pnpm" volta install pnpm
    updated_any=true
  fi

  if [[ "$updated_any" == false ]]; then
    note "Volta is installed, but no managed default tools were detected. If you want to move a default runtime forward, run: volta install node npm"
  fi
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
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

ensure_prompt_available

if [[ "$skip_backup_check" == true ]]; then
  log "Time Machine safety gate"
  printf 'Skipped: --skip-backup-check was passed.\n'
elif ! require_time_machine_backup; then
  exit 1
fi

if command -v brew >/dev/null 2>&1; then
  run_mutating_step "Homebrew update" brew update
  preview_step "Homebrew outdated formulae and standard casks" brew outdated --verbose
  run_mutating_step "Homebrew upgrade formulae and standard casks" brew upgrade
  if [[ "$use_greedy_casks" == true ]]; then
    preview_step "Homebrew outdated greedy casks" brew outdated --cask --greedy --verbose
    run_mutating_step "Homebrew greedy cask upgrade" brew upgrade --cask --greedy
  else
    note "Skipping greedy cask upgrades. Use --greedy-casks if you want to force auto-updating casks."
  fi
  preview_step "Homebrew cleanup dry run" brew cleanup -n
  run_mutating_step "Homebrew cleanup" brew cleanup
  run_step "Homebrew doctor" brew doctor
else
  missing_tool "brew" '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' "https://brew.sh/"
fi

if command -v npm >/dev/null 2>&1; then
  preview_step "npm outdated global packages" npm outdated -g --depth=0
  run_mutating_step "npm global package updates" npm update -g
  run_mutating_step "npm cache verify" npm cache verify
else
  note 'Not installed: npm. Install Node first, for example with "volta install node" or "brew install node".'
fi

if command -v mas >/dev/null 2>&1; then
  preview_step "Mac App Store outdated apps" mas outdated
  run_mutating_step "Mac App Store updates" mas upgrade
else
  missing_tool "mas" "brew install mas" "https://github.com/mas-cli/mas"
fi

if command -v uv >/dev/null 2>&1; then
  preview_step "uv outdated tools" uv tool list --outdated
  run_mutating_step "uv tool upgrades" uv tool upgrade --all
  preview_step "uv processes currently running (cache may be locked by these)" bash -c 'pgrep -fl uv || true'
  run_mutating_step "uv cache prune" uv cache prune
else
  missing_tool "uv" "brew install uv" "https://docs.astral.sh/uv/"
fi

if command -v pipx >/dev/null 2>&1; then
  preview_step "pipx installed packages" pipx list
  note "pipx does not provide a compact outdated summary here, so the installed package list is shown before upgrades."
  run_mutating_step "pipx package upgrades" pipx upgrade-all
  run_mutating_step "pipx shared library upgrades" pipx upgrade-shared
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
  run_mutating_step "rustup toolchain updates" rustup update
  run_step "rustup check" rustup check
else
  missing_tool "rustup" "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh" "https://www.rust-lang.org/tools/install"
fi


if command -v mise >/dev/null 2>&1; then
  preview_step "mise current tools" bash -lc 'cd "$HOME" && mise list'
  note "mise does not expose a single generic outdated summary here, so the current tool list is shown before upgrades."
  run_mutating_step "mise tool upgrades" bash -lc 'cd "$HOME" && mise upgrade'
  run_mutating_step "mise cache prune" mise cache prune
  run_step "mise doctor" mise doctor
else
  missing_tool "mise" "brew install mise" "https://mise.jdx.dev/getting-started.html"
fi

if command -v softwareupdate >/dev/null 2>&1; then
  preview_step "Available macOS software updates" softwareupdate -l
  run_mutating_step "macOS software updates" softwareupdate -i -a
else
  note "softwareupdate is not available on this machine."
fi

if [[ "$failures" -gt 0 ]]; then
  printf '\nFinished with %s failed step(s).\n' "$failures" >&2
  exit 1
fi

printf '\nAll update steps finished successfully.\n'
