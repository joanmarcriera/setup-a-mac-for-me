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
brew install bash wget vim uv tig htop tree tmux jq ncurses gh go pandoc jira-cli volta ffmpeg
brew install --cask iterm2 orbstack google-chrome google-chrome@canary vivaldi duckduckgo visual-studio-code github codex claude antigravity keyboard-maestro rectangle-pro karabiner-elements betterdisplay obsidian logseq mailmate@beta keepassxc spotify slack discord microsoft-edge microsoft-office microsoft-teams onedrive microsoft-outlook microsoft-remote-desktop skim adobe-acrobat-reader pdf-expert shottr kap
```

3. Copy the macOS defaults commands you want from `docs/macos-defaults.html`.

4. Restore app state and licenses for Vivaldi, Keyboard Maestro, Rectangle Pro, VS Code, Obsidian, and the rest of the daily stack.

5. Verify the machine.

```sh
./scripts/verify-setup.sh workstation
```

## Keep The Mac Updated

If you want a small `~/bin` helper, copy the updater script from this repo:

```sh
cp scripts/update-mac.sh ~/bin/update-mac
chmod +x ~/bin/update-mac
```

It updates:

- Homebrew formulae and casks
- npm global packages
- uv, pipx, Volta, rustup, and mise if they are installed
- macOS software updates
- Mac App Store apps if `mas` is installed

It refuses to run upgrades unless Time Machine reports both a latest backup and a visible destination, so it only upgrades when the backup path is available.

It starts with a **pre-flight summary**: macOS version, free disk, the last Time Machine backup and its age, followed by a grouped, risk-annotated **upgrade plan** of what would change. The plan flags, using local checks only (no network, no CVE lookups):

- `!!` **major version jumps** (leading version number changed, or a `0.x` minor bump) — the ones most likely to break something, so review release notes first
- `!!` a **macOS update that requires a restart**
- `~` **pre-release channels** (auto-updating `@beta` / `@canary` / nightly software)
- **pinned** formulae that will not upgrade

Everything else is summarized as routine counts. If `python3` is unavailable the plan degrades to a compact per-tool count line.

When a macOS update is pending, the summary also prints a **recommended order**: install the macOS update first, reboot, then re-run `update-mac` for Homebrew and everything else. A macOS update can change the Command Line Tools and system libraries that Homebrew links against, so upgrading brew on the fresh system avoids mismatches. The note reminds you to back up with Time Machine first and shows your last backup.

By default it runs step by step:

- it previews what it can with non-mutating checks
- it asks **once per tool** with `Yes`, `No`, `Skip`, `All`, or `Quit`
- choose `All` at any prompt to approve that tool and every remaining one without further prompts

To preview everything without changing anything (and without the Time Machine gate), run:

```sh
update-mac --dry-run
```

It prints the summary, shows what each tool would do, then exits having mutated nothing. This is the safe way to see what an update would touch.

By default it does **not** force auto-updating casks. If you want that behavior anyway, run:

```sh
update-mac --greedy-casks
```

If you want it to run straight through without prompts, use:

```sh
update-mac --yes
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
- Slack, Discord, Microsoft apps, and PDF readers/editors in the default workstation path
- Tailscale and Little Snitch in the network slice
- Time Machine to TrueNAS first, with Kopia only as an optional extra
- no App Expose, `autojump`, `zsh-syntax-highlighting`, `pnpm`, Dropover, iBar, Whimsical, or Notion
