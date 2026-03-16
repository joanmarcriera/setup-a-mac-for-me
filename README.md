# mac.riera.co.uk

Opinionated MacBook Pro rebuild notes for Joan Marc Riera.

This repo now serves two jobs:

- a public GitHub Pages site under `docs/`
- a practical rebuild kit for the next clean Mac setup

## What Changed

The repo is now organized around one source of truth for install groups:

- `data/install-groups.json`: Homebrew groups and presets
- `brew/`: generated `Brewfile.*` files and copy/paste commands
- `docs/`: static GitHub Pages site with raw Homebrew commands and direct macOS preference commands
- `scripts/apply-macos-defaults.sh`: optional helper for the same Dock and Launchpad defaults shown on the site
- `scripts/verify-setup.sh`: checks installed apps plus the scripted macOS defaults
- `scripts/generate_brew_artifacts.py`: regenerates `brew/` files and the installer data used by the site
- `scripts/check_docs.py`: validates local site links and required Pages files

## Quick Start

1. Install Homebrew.

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

2. Copy the workstation commands from the Homebrew page or `brew/README.md`.

```sh
brew install bash wget vim uv tig htop tree tmux jq ncurses gh go pandoc jira-cli volta kopia ffmpeg
brew install --cask iterm2 orbstack google-chrome google-chrome@canary vivaldi duckduckgo visual-studio-code github codex claude antigravity keyboard-maestro rectangle-pro karabiner-elements betterdisplay obsidian logseq mailmate@beta keepassxc spotify kopiaui google-drive shottr kap
```

3. Copy the macOS defaults commands you want from `docs/macos-defaults.html`.

4. Restore app state and licenses for Vivaldi, Keyboard Maestro, Rectangle Pro, VS Code, Obsidian, and the rest of the daily stack.

5. Verify the machine.

```sh
./scripts/verify-setup.sh workstation
```

## Local Site Preview

```sh
python3 -m http.server --directory docs 8000
```

Then open `http://127.0.0.1:8000`.

## Updating The Install Data

Edit `data/install-groups.json`, then regenerate the derived files:

```sh
python3 scripts/generate_brew_artifacts.py
python3 scripts/build_search_index.py
python3 scripts/check_docs.py
```

CI also checks that generated files are up to date and that the Pages site still resolves its local assets correctly.

## Current Setup Shape

This repo reflects the current preferences for the next rebuild:

- Vivaldi and DuckDuckGo
- dark terminal with about 20% transparency
- zsh with a minimal plugin set
- Keyboard Maestro instead of Alfred or Raycast
- VS Code, Codex, Claude, Antigravity, OrbStack
- Obsidian, Logseq, MailMate beta, Shottr, Kap, Rectangle Pro, BetterDisplay
- Tailscale and Little Snitch in the network slice
- Time Machine to TrueNAS first, with Kopia only as an optional extra
- no App Expose, `autojump`, `zsh-syntax-highlighting`, `pnpm`, Dropover, iBar, Whimsical, or Notion
