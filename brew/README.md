# Homebrew Install Commands

This folder is generated from `data/install-groups.json`.

Copy and paste the commands you want.

The default bundles are listed first, followed by the smaller group commands.

## Default Bundles

### Minimal

Enough to browse, code, and get back into the repo quickly.

```sh
brew install bash wget vim uv tig htop tree tmux jq ncurses gh
brew install --cask iterm2 google-chrome google-chrome@canary vivaldi duckduckgo visual-studio-code github codex claude antigravity keyboard-maestro rectangle-pro karabiner-elements betterdisplay obsidian logseq mailmate@beta keepassxc spotify slack discord
```

### Workstation

The usual day-one rebuild for daily work.

```sh
brew install bash wget vim uv tig htop tree tmux jq ncurses gh go pandoc jira-cli volta ffmpeg
brew install --cask iterm2 orbstack google-chrome google-chrome@canary vivaldi duckduckgo visual-studio-code github codex claude antigravity keyboard-maestro rectangle-pro karabiner-elements betterdisplay obsidian logseq mailmate@beta keepassxc spotify slack discord microsoft-edge microsoft-office microsoft-teams onedrive microsoft-outlook microsoft-remote-desktop skim adobe-acrobat-reader pdf-expert shottr kap
```

### Full

Daily rebuild plus network and support tools.

```sh
brew install bash wget vim uv tig htop tree tmux jq ncurses gh go pandoc jira-cli volta ffmpeg telnet rclone ipmitool openssl lftp mtr nmap net-snmp
brew install --cask iterm2 orbstack google-chrome google-chrome@canary vivaldi duckduckgo visual-studio-code github codex claude antigravity keyboard-maestro rectangle-pro karabiner-elements betterdisplay obsidian logseq mailmate@beta keepassxc spotify slack discord microsoft-edge microsoft-office microsoft-teams onedrive microsoft-outlook microsoft-remote-desktop skim adobe-acrobat-reader pdf-expert shottr kap tailscale-app little-snitch rustdesk netspot
```

## Individual Groups

### CLI

Core shell and terminal tools for day one.

```sh
brew install bash wget vim uv tig htop tree tmux jq ncurses gh
brew install --cask iterm2
```

### Dev

Coding and writing tools that belong on every workstation rebuild.

```sh
brew install go pandoc jira-cli volta
brew install --cask orbstack
```

### Browsers + AI

Browser and coding assistants used in the daily workflow.

```sh
brew install --cask google-chrome google-chrome@canary vivaldi duckduckgo visual-studio-code github codex claude antigravity
```

### Productivity

Window management, keyboard automation, notes, and personal utilities.

```sh
brew install --cask keyboard-maestro rectangle-pro karabiner-elements betterdisplay obsidian logseq mailmate@beta keepassxc spotify slack discord
```

### Microsoft

Microsoft apps that are common enough to keep ready on a work machine.

```sh
brew install --cask microsoft-edge microsoft-office microsoft-teams onedrive microsoft-outlook microsoft-remote-desktop
```

### PDF

PDF readers and editors kept ready for paperwork, review, and annotation.

```sh
brew install --cask skim adobe-acrobat-reader pdf-expert
```

### Backup

Optional backup extras if Time Machine to TrueNAS is not enough.

```sh
brew install kopia
brew install --cask kopiaui google-drive
```

### Capture

Screenshot, recording, and media tooling.

```sh
brew install ffmpeg
brew install --cask shottr kap
```

### Network

Diagnostics, remote access, and support tooling kept out of the default rebuild.

```sh
brew install telnet rclone ipmitool openssl lftp mtr nmap net-snmp
brew install --cask tailscale-app little-snitch rustdesk netspot
```

## Notes

- zsh stays minimal: no autojump and no zsh-syntax-highlighting.
- Node.js version management goes through Volta. pnpm is intentionally excluded.
- OrbStack is the local container and Linux path. Docker Desktop stays out of the default rebuild.
- Chrome, Chrome Canary, and Vivaldi all stay available because they each cover a different browser role during setup and testing.
- DuckDuckGo is the search-first companion.
- Antigravity is part of the current AI toolchain.
- Keyboard Maestro replaces Alfred, Raycast, and standalone clipboard managers.
- Keyboard Maestro and Rectangle Pro still require paid licenses after install.
- BetterDisplay stays because external monitor scaling and brightness control keep coming up.
- MailMate beta is the default on Apple Silicon because the stable cask currently requires Rosetta 2.
- KeeWeb was intentionally replaced with KeePassXC because KeeWeb's desktop releases have stalled.
- Slack and Discord stay in productivity because they are part of the day-to-day communications path, not a special-case install.
- Vivaldi can still be the main browser even when Edge is installed for compatibility work and Microsoft account flows.
- Office, Outlook, Teams, OneDrive, and Remote Desktop all stay together because they usually arrive as a package deal in work environments.
- Skim is the fast lightweight reader. Acrobat Reader covers the Adobe-heavy edge cases. PDF Expert covers editing and annotation.
- If Time Machine to the TrueNAS or NFS target already gives a complete backup and clean restore path, skip this group.
- Kopia stays optional for cases where an extra encrypted offsite copy or repository-style verification is still useful.
- Shottr and Kap stay in the default workstation because they are used often.
- Useful when the Mac is doubling as a support or network box.
- The current Homebrew cask token is tailscale-app, not tailscale.
- Alfred, Raycast, `pnpm`, Dropover, iBar, Whimsical, and Notion are intentionally excluded.
