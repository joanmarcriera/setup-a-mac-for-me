#!/usr/bin/env bash
#
# apply-macos-defaults.sh - the small set of macOS defaults documented on the site
# (docs/index.html -> "macOS Defaults"): Tap to Click, Dock autohide speed, Launchpad grid.
# This file is the single place those values live; verify-setup.sh calls `--check`.
#
# Usage:
#   scripts/apply-macos-defaults.sh [--dry-run | --check | --reset | -h]
#
#   (no flag)    apply the defaults, then restart the Dock (killall Dock)
#   --dry-run    print every command that would run; change nothing, do not touch the Dock
#   --check      read-only: compare current values with the expected ones, exit 1 on mismatch
#   --reset      undo: delete the keys this script writes, so macOS falls back to its own
#                defaults (Dock autohide speed, Launchpad grid, Tap to Click off). Also
#                spelled --restore. Supports --dry-run.
#
# Notes:
#  - Launchpad was replaced by the Apps view in macOS 26 (Tahoe), so the springboard-*
#    grid keys are skipped there (they have no effect).
#  - Three-finger drag, App Expose and per-app settings are manual steps (see the site).
#  - Works with macOS /bin/bash 3.2.

set -euo pipefail

mode=apply
dry=false

for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) dry=true ;;
    --check) mode=check ;;
    --reset|--restore) mode=reset ;;
    -h|--help) sed -n '3,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; /^#!/d'; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done
# --dry-run alone means "dry-run the apply".

macos_major=$(sw_vers -productVersion 2>/dev/null | cut -d. -f1 || true)
macos_major=${macos_major:-0}

# Table: scope|domain|key|type|value
#   scope  = dock (needs a Dock restart), host (uses `defaults -currentHost`), user,
#            legacy (written/reset like user, but not verified: modern macOS reads the
#            trackpad domains above and often leaves this global key unset)
#   type   = float|int|bool (the value `defaults read` prints for bool is 1/0)
# Values mirror docs/index.html exactly; edit both together.
entries=(
  "user|com.apple.AppleMultitouchTrackpad|Clicking|bool|true"
  "user|com.apple.driver.AppleBluetoothMultitouch.trackpad|Clicking|bool|true"
  "host|NSGlobalDomain|com.apple.mouse.tapBehavior|int|1"
  "legacy|NSGlobalDomain|com.apple.mouse.tapBehavior|int|1"
  "dock|com.apple.dock|autohide-time-modifier|float|0.5"
  "dock|com.apple.dock|autohide-delay|int|0"
)
if [[ "$macos_major" -lt 26 ]]; then
  entries+=("dock|com.apple.dock|springboard-columns|int|10" "dock|com.apple.dock|springboard-rows|int|8")
else
  echo "Skipping Launchpad grid keys: Launchpad no longer exists on macOS $macos_major." >&2
fi

# Run (or just print) a command. Printing uses %q-free simple quoting; none of our
# arguments contain spaces.
run() {
  if [[ "$dry" == true ]]; then
    echo "+ $*"
  else
    "$@"
  fi
}

# defaults wrapper honouring the `host` scope.
defaults_cmd() {
  local scope="$1"
  shift
  if [[ "$scope" == host ]]; then
    defaults -currentHost "$@"
  else
    defaults "$@"
  fi
}

# Same, but as a printable/runnable argv prefix for run().
dcmd() {
  if [[ "$1" == host ]]; then echo "defaults -currentHost"; else echo "defaults"; fi
}

need_dock_restart=false
mismatches=0

for entry in "${entries[@]}"; do
  IFS='|' read -r scope domain key type value <<<"$entry"
  [[ "$scope" == dock ]] && need_dock_restart=true
  [[ "$mode" == check && "$scope" == legacy ]] && continue
  # shellcheck disable=SC2046  # intentional word splitting of the prefix
  case "$mode" in
    apply) run $(dcmd "$scope") write "$domain" "$key" "-$type" "$value" ;;
    reset) run $(dcmd "$scope") delete "$domain" "$key" 2>/dev/null || true ;;
    check)
      got=$(defaults_cmd "$scope" read "$domain" "$key" 2>/dev/null || true)
      want=$value
      [[ "$type" == bool ]] && { [[ "$value" == true ]] && want=1 || want=0; }
      if [[ "$got" != "$want" ]]; then
        mismatches=$((mismatches + 1))
        echo "Default mismatch: $domain $key expected $want, got ${got:-<unset>}"
      fi
      ;;
  esac
done

case "$mode" in
  check)
    [[ "$mismatches" -eq 0 ]] && echo "macOS defaults match." && exit 0
    exit 1
    ;;
esac

if [[ "$need_dock_restart" == true ]]; then
  if [[ "$dry" == true ]]; then echo "+ killall Dock"; else killall Dock >/dev/null 2>&1 || true; fi
fi

if [[ "$dry" == true ]]; then
  echo "Dry run: nothing was changed."
elif [[ "$mode" == reset ]]; then
  echo "Reset the keys this script manages; macOS built-in defaults apply again."
else
  cat <<'MSG'
Applied Tap to Click, Dock autohide speed and (pre-macOS 26) Launchpad grid defaults.

Manual follow-up still required:
- Enable three-finger drag (System Settings > Accessibility > Pointer Control > Trackpad Options).
- Keep App Expose disabled.
- Point Keyboard Maestro at your preferred launcher and clipboard shortcuts.
- Set Vivaldi as the default browser and DuckDuckGo as the default search engine.
MSG
fi
