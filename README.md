# mac.riera.co.uk

Opinionated MacBook Pro rebuild notes for Joan Marc Riera.

## Usage

This repo publishes a reusable Mac setup guide and Homebrew installer. Visit [mac.riera.co.uk](https://mac.riera.co.uk/) for the interactive site, or copy install commands directly from `brew/README.md`.

To rebuild a Mac:
1. Install Homebrew: `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
2. Copy the install commands you need from `brew/README.md` (or the site)
3. Run the verify script: `./scripts/verify-setup.sh workstation`
4. To keep your Mac updated: `cp scripts/update-mac.sh ~/bin/update-mac && chmod +x ~/bin/update-mac && update-mac`

To develop or customize:
- Edit `data/install-groups.json` with your app list
- Run `python3 scripts/generate_brew_artifacts.py && python3 scripts/build_search_index.py && python3 scripts/check_docs.py`
- Preview the site: `python3 -m http.server --directory docs 8000` → http://127.0.0.1:8000

This repo now serves two jobs:

- a public GitHub Pages site under `docs/`
- a practical rebuild kit for the next clean Mac setup

## What Changed

The repo is now organized around one source of truth for install groups:

- `data/install-groups.json`: Homebrew groups and presets
- `brew/`: generated `Brewfile.*` files and copy/paste commands
- `docs/`: static GitHub Pages site with raw Homebrew commands and direct macOS preference commands
- `scripts/apply-macos-defaults.sh`: optional helper for the Tap to Click, Dock and Launchpad defaults shown on the site (`--dry-run`, `--check`, `--reset`)
- `scripts/verify-setup.sh`: data-driven check of a bundle's taps, formulae, casks (and Mac App Store apps if listed) plus the scripted macOS defaults
- `scripts/drift-report.sh`: read-only "what changed since I set this up" report (installed vs `data/install-groups.json`)
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

## Verify, Defaults And Drift

All three scripts are read-only unless stated, work with macOS `/bin/bash` 3.2, and need only `python3`.

```sh
./scripts/verify-setup.sh [bundle]        # default bundle: workstation; --list shows bundle ids
./scripts/apply-macos-defaults.sh --dry-run   # print the defaults commands, change nothing
./scripts/apply-macos-defaults.sh             # apply (writes defaults, restarts the Dock)
./scripts/apply-macos-defaults.sh --check     # read-only compare, exit 1 on mismatch
./scripts/apply-macos-defaults.sh --reset     # delete the keys it manages (supports --dry-run)
./scripts/drift-report.sh [--json] [--bundle ID] [--ignore FILE] [--no-mas]
```

- `verify-setup.sh` builds its expected list from `data/install-groups.json` (a tap-qualified name matches the installed short name) and gets the defaults from `apply-macos-defaults.sh --check`, so there are no hardcoded app lists. Exit 0 = good, 1 = something missing, 2 = usage error.
- `apply-macos-defaults.sh` is the one place the defaults live. Launchpad was replaced by the Apps view in macOS 26, so the `springboard-*` grid keys are skipped there.
- `drift-report.sh` prints three things: installed but not in the repo (Homebrew leaves, casks, Mac App Store apps), in the repo but not installed, and copy/paste suggestions. `--json` gives one JSON object. Exit code is 0 when there is no drift, 1 when there is, 2 on error, so it works from cron or launchd (`drift-report.sh --json > ~/drift.json || osascript -e 'display notification "Mac setup drifted"'`). Put names you deliberately keep out of the repo in `~/.config/mac-drift-ignore` (one per line, `#` comments) to silence them.

## Keep The Mac Updated

If you want a small `~/bin` helper, copy the updater script from this repo:

```sh
cp scripts/update-mac.sh ~/bin/update-mac
chmod +x ~/bin/update-mac
```

It updates:

- Homebrew formulae and casks
- npm global packages
- uv tools, pipx, Volta, rustup, and mise if they are installed
- macOS software updates
- Mac App Store apps if `mas` is installed

It refuses to run upgrades unless Time Machine reports both a latest backup and a visible destination, and that backup must be under 7 days old (a warning appears after 2 days). `--skip-backup-check` bypasses the gate.

It starts with a **pre-flight summary**: macOS version, free disk, the last Time Machine backup and its age, the Xcode and Command Line Tools versions. Every scan (Homebrew, npm, uv, Mac App Store, mise, rustup and `softwareupdate`) then runs **in parallel**, and the result is shown as an **upgrade-plan table**, riskiest rows first. The Risk column flags, using local checks only (no CVE lookups):

- `MAJOR` — a major version jump (or a `0.x` minor bump); review release notes first
- `restart` — a macOS update that requires a restart
- `pre-release` — beta / canary / nightly versions
- `pinned` — formulae that will not upgrade

Below the plan, a **Needs attention** table lists things that no longer work or are on the way out: Homebrew formulae/casks that upstream deprecated or disabled, deprecated global npm packages (with the registry's replacement hint), Volta packages whose files are gone, and dangling symlinks in `/opt/homebrew/bin`, `/usr/local/bin` and `~/.local/bin`. These are reported with a suggested fix; only broken Volta packages can be removed by `update-mac` itself, through the **Cleanup** entry on the selection screen (never by `--yes`).

**Major version jumps are held back by default** (they show in the plan but are not applied): npm packages and Homebrew upgrades skip them, and Volta keeps Node/npm/Yarn/pnpm on their current major. Press `m` on the selection screen, or pass `--major`, to include them. Global npm packages are upgraded one at a time (`volta install <pkg>@latest` when Volta is present, since `npm update -g` fights Volta), so one broken package cannot abort the rest, and failures are listed at the end.

Under Volta the npm scan reads Volta's own package list (plain `npm outdated -g` would only see the npm bundled in Volta's Node image), pipx packages are checked against PyPI, and a tool whose scan fails is shown as `scan FAILED` rather than "0 outdated". uv and mise also honour the major hold; Mac App Store and rustup do not, and the macOS row says so.

Routine (same-major) updates are collapsed into one line per tool; add `--verbose` to list them. If `python3` is unavailable the plan degrades to a compact per-tool count line.

When a macOS update is pending, the summary also prints a **recommended order**: install the macOS update first, reboot, then re-run `update-mac` for Homebrew and everything else. A macOS update can change the Command Line Tools and system libraries that Homebrew links against, so upgrading brew on the fresh system avoids mismatches. The note reminds you to back up with Time Machine first and shows your last backup. Only genuine macOS system updates trigger it — XProtect config data, Safari and the Command Line Tools do not. It is advisory: the run order is unchanged, so the note also states that this run still does Homebrew first (and, under `--yes`, that it will not stop to let you change your mind).

Then a **selection screen** lets you choose what to go through: `↑/↓` or `j/k` move, `space` toggles a tool, `a` selects all, `n` none, `m` toggles major jumps, `q` quits, and **`Enter` is the single approval**. The ticked tools then run one step at a time with no further prompts, and a results table is printed at the end. macOS is never pre-ticked. `--ask` restores the old per-tool `Yes/No/Skip/All/Quit` prompts.

To preview everything without changing anything (and without the Time Machine gate), run:

```sh
update-mac --dry-run
```

It prints the summary, shows what each tool would do, then exits having mutated nothing. This is the safe way to see what an update would touch.

By default it does **not** force auto-updating casks. If you want that behavior anyway, run:

```sh
update-mac --greedy-casks
```

If a major macOS upgrade (for example 26 to 27) is listed, `update-mac` says so. The macOS update is never pre-ticked on the selection screen, and `--yes` skips it unless you also pass `--with-macos`. Only same-major updates are installed (by label); a major OS upgrade is always left for you to do by hand. Pass `--skip-macos` to not be asked at all and do it by hand:

```sh
update-mac --skip-macos
```

`brew doctor`, `mise doctor` and the final `rustup check` are informational: their warnings are shown but do not count as failed steps.

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
