#!/usr/bin/env bash

set -euo pipefail

restore=false

if [[ "${1:-}" == "--restore" ]]; then
  restore=true
fi

if [[ "$restore" == true ]]; then
  defaults delete com.apple.dock autohide-time-modifier >/dev/null 2>&1 || true
  defaults delete com.apple.dock autohide-delay >/dev/null 2>&1 || true
  defaults write com.apple.dock springboard-rows Default
  defaults write com.apple.dock springboard-columns Default
  killall Dock >/dev/null 2>&1 || true
  echo "Restored Dock and Launchpad defaults."
  exit 0
fi

defaults write com.apple.dock autohide-time-modifier -float 0.5
defaults write com.apple.dock autohide-delay -int 0
defaults write com.apple.dock springboard-columns -int 10
defaults write com.apple.dock springboard-rows -int 8
killall Dock >/dev/null 2>&1 || true

cat <<'EOF'
Applied Dock and Launchpad defaults.

Manual follow-up still required:
- Enable Tap to Click.
- Enable three-finger drag.
- Keep App Expose disabled.
- Point Keyboard Maestro at your preferred launcher and clipboard shortcuts.
- Set Vivaldi as the default browser and DuckDuckGo as the default search engine.
EOF
