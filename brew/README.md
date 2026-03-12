# Homebrew Install Commands

This folder is generated from `data/install-groups.json`.

It keeps Homebrew installs in three formats:

- one-command bundles
- grouped `brew bundle` files
- raw `brew install` commands

## Fastest Options

```sh
brew bundle --file brew/Brewfile.minimal
brew bundle --file brew/Brewfile.workstation
brew bundle --file brew/Brewfile.all
```

## Grouped Bundle Commands

```sh
brew bundle --file brew/Brewfile.cli
brew bundle --file brew/Brewfile.dev
brew bundle --file brew/Brewfile.browsers-ai
brew bundle --file brew/Brewfile.productivity
brew bundle --file brew/Brewfile.capture
brew bundle --file brew/Brewfile.network
```

## Raw Brew Commands

### CLI

Core shell and terminal tools for day one.

```sh
brew install bash wget vim uv tig htop tree tmux jq ncurses
```

### Dev

Coding and writing tools that belong on every workstation rebuild.

```sh
brew install go pandoc jira-cli volta
```

### Browsers + AI

Browser and coding assistants used in the daily workflow.

```sh
brew install --cask vivaldi duckduckgo visual-studio-code codex claude
```

### Productivity

Window management, keyboard automation, notes, and personal utilities.

```sh
brew install --cask keyboard-maestro rectangle-pro karabiner-elements obsidian keeweb spotify
```

### Capture

Screenshot, recording, and media tooling.

```sh
brew install ffmpeg
```

```sh
brew install --cask shottr kap
```

### Network

Diagnostics, remote access, and support tooling kept out of the default rebuild.

```sh
brew install telnet rclone ipmitool openssl lftp mtr nmap net-snmp
```

```sh
brew install --cask rustdesk netspot
```

## Notes

- zsh stays minimal: no autojump and no zsh-syntax-highlighting.
- Node.js version management goes through Volta. pnpm is intentionally excluded.
- Vivaldi is the main browser. DuckDuckGo is the search-first companion.
- Keyboard Maestro replaces Alfred, Raycast, and standalone clipboard managers.
- Keyboard Maestro and Rectangle Pro still require paid licenses after install.
- Shottr and Kap stay in the default workstation because they are used often.
- Useful when the Mac is doubling as a support or network box.
- Alfred, Raycast, `pnpm`, Dropover, iBar, Whimsical, and Notion are intentionally excluded.
