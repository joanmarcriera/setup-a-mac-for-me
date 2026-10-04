# Homebrew Install Commands

This folder is generated from `data/install-groups.json`.

Copy and paste the commands you want.

The default bundles are listed first, followed by the smaller group commands.

## Default Bundles

### Minimal

Enough to browse, code, and get back into the repo quickly.

```sh
brew install bash wget vim uv tig htop tree tmux jq gh mas fzf ripgrep-all dust ncdu watch gping jdupes
brew install --cask iterm2 google-chrome google-chrome@canary vivaldi comet duckduckgo visual-studio-code codex claude antigravity keyboard-maestro rectangle-pro karabiner-elements betterdisplay obsidian logseq mailmate@beta spotify slack discord telegram-desktop
```

### Workstation

The usual day-one rebuild for daily work.

```sh
brew install bash wget vim uv tig htop tree tmux jq gh mas fzf ripgrep-all dust ncdu watch gping jdupes go volta mise pipx pandoc shellcheck git-cliff git-filter-repo git-lfs cmake hugo forgejo-cli colima docker docker-compose ollama llama.cpp whisper.cpp whisperkit-cli llmfit opencode herdr rtk qpdf poppler tesseract weasyprint pango ffmpeg yt-dlp gallery-dl gitleaks syft grype ykman
brew install --cask iterm2 github google-chrome google-chrome@canary vivaldi comet duckduckgo visual-studio-code codex claude antigravity antigravity-cli lm-studio codexbar hive-app supacode t3-code meetily keyboard-maestro rectangle-pro karabiner-elements betterdisplay obsidian logseq mailmate@beta spotify slack discord telegram-desktop typora markedit zotero anki libreoffice drawio yed excalidrawz microsoft-edge microsoft-teams skim adobe-acrobat-reader shottr vlc blackhole-2ch blender bitwarden keepassxc
mas install 462054704  # Microsoft Word
mas install 462058435  # Microsoft Excel
mas install 1295203466  # Windows App
```

### Full

Daily rebuild plus cloud, mobile, backup, network and support tools.

```sh
brew install bash wget vim uv tig htop tree tmux jq gh mas fzf ripgrep-all dust ncdu watch gping jdupes go volta mise pipx pandoc shellcheck git-cliff git-filter-repo git-lfs cmake hugo forgejo-cli colima docker docker-compose ollama llama.cpp whisper.cpp whisperkit-cli llmfit opencode herdr rtk qpdf poppler tesseract weasyprint pango ffmpeg yt-dlp gallery-dl gitleaks syft grype ykman opentofu oci-cli googleworkspace-cli openjdk@21 gradle xcodegen swiftlint rclone mtr nmap
brew install --cask iterm2 github google-chrome google-chrome@canary vivaldi comet duckduckgo visual-studio-code codex claude antigravity antigravity-cli lm-studio codexbar hive-app supacode t3-code meetily keyboard-maestro rectangle-pro karabiner-elements betterdisplay obsidian logseq mailmate@beta spotify slack discord telegram-desktop typora markedit zotero anki libreoffice drawio yed excalidrawz microsoft-edge microsoft-teams skim adobe-acrobat-reader shottr vlc blackhole-2ch blender bitwarden keepassxc gcloud-cli android-studio android-commandlinetools android-platform-tools google-drive tailscale-app netspot
mas install 462054704  # Microsoft Word
mas install 462058435  # Microsoft Excel
mas install 1295203466  # Windows App
mas install 497799835  # Xcode
mas install 640199958  # Developer
```

## Individual Groups

### CLI

Core shell and terminal tools for day one.

```sh
brew install bash wget vim uv tig htop tree tmux jq gh mas fzf ripgrep-all dust ncdu watch gping jdupes
brew install --cask iterm2
```

### Dev

Coding and writing tools that belong on every workstation rebuild.

```sh
brew install go volta mise pipx pandoc shellcheck git-cliff git-filter-repo git-lfs cmake hugo forgejo-cli
brew install --cask github
```

### Containers

Local containers without Docker Desktop: colima VM plus the docker CLI.

```sh
brew install colima docker docker-compose
```

### Browsers + AI

Browsers and coding assistants used in the daily workflow.

```sh
brew install --cask google-chrome google-chrome@canary vivaldi comet duckduckgo visual-studio-code codex claude antigravity
```

### AI + Local LLM

Local models, speech-to-text and agent tooling that run on Apple Silicon.

```sh
brew install ollama llama.cpp whisper.cpp whisperkit-cli llmfit opencode herdr rtk
brew install --cask antigravity-cli lm-studio codexbar hive-app supacode t3-code meetily
```

### Cloud + IaC

Infrastructure-as-code and cloud CLIs.

```sh
brew install opentofu oci-cli googleworkspace-cli
brew install --cask gcloud-cli
```

### Apple + Android Dev

Toolchains for shipping Apple and Android apps.

```sh
brew install openjdk@21 gradle xcodegen swiftlint
brew install --cask android-studio android-commandlinetools android-platform-tools
mas install 497799835  # Xcode
mas install 640199958  # Developer
```

### Security + Audit

Secret scanning, SBOM and vulnerability scans, hardware keys, password managers.

```sh
brew install gitleaks syft grype ykman
brew install --cask bitwarden keepassxc
```

### Productivity

Window management, keyboard automation, notes, and personal utilities.

```sh
brew install --cask keyboard-maestro rectangle-pro karabiner-elements betterdisplay obsidian logseq mailmate@beta spotify slack discord telegram-desktop
```

### Writing + Diagrams

Markdown editing, reference management, flashcards and diagramming.

```sh
brew install --cask typora markedit zotero anki libreoffice drawio yed excalidrawz
```

### Microsoft

Microsoft apps that are common enough to keep ready on a work machine.

```sh
brew install --cask microsoft-edge microsoft-teams
mas install 462054704  # Microsoft Word
mas install 462058435  # Microsoft Excel
mas install 1295203466  # Windows App
```

### PDF

PDF readers and command-line PDF and OCR tooling.

```sh
brew install qpdf poppler tesseract weasyprint pango
brew install --cask skim adobe-acrobat-reader
```

### Backup

Optional cloud sync; Time Machine to TrueNAS is the real backup.

```sh
brew install --cask google-drive
```

### Capture + Media

Screenshot, recording, download and media tooling.

```sh
brew install ffmpeg yt-dlp gallery-dl
brew install --cask shottr vlc blackhole-2ch blender
```

### Network

Diagnostics, remote access, and support tooling kept out of the default rebuild.

```sh
brew install rclone mtr nmap
brew install --cask tailscale-app netspot
```

## Retired

Previously listed, no longer part of the rebuild:

- `orbstack` (cask): Replaced by colima + docker CLI.
- `jira-cli` (formula): No longer installed or used.
- `kopia` (formula): Not installed; backups handled by Time Machine, ZFS replication and rclone.
- `kopiaui` (cask): Not installed; see kopia.
- `lftp` (formula): Not installed.
- `telnet` (formula): Not installed.
- `ipmitool` (formula): Not installed.
- `net-snmp` (formula): Not installed.
- `ncurses` (formula): Dependency only; not a deliberate install.
- `openssl` (formula): Dependency only; not a deliberate install.
- `little-snitch` (cask): Not installed.
- `rustdesk` (cask): Not installed; Tailscale + Windows App cover remote access.
- `kap` (cask): Not installed.
- `pdf-expert` (cask): Not installed.
- `microsoft-office` (cask): Replaced by Word and Excel from the Mac App Store.
- `microsoft-outlook` (cask): Not installed; MailMate is the mail client.
- `onedrive` (cask): Not installed.
- `microsoft-remote-desktop` (cask): Cask removed from Homebrew; replaced by Windows App (mas).
- `gemini-cli` (formula): Deprecated upstream (disabled 2026-12-18); use antigravity-cli.
- `john-jumbo` (formula): One-off recovery tool; intentionally not in the rebuild.

## Notes

- zsh stays minimal: no autojump and no zsh-syntax-highlighting.
- mas (Mac App Store CLI) is here because the rebuild installs Word, Excel, Xcode and others through it.
- ncurses was dropped from the explicit list: it is only a dependency and Homebrew pulls it in when needed.
- Node.js version management goes through Volta; mise covers the other runtimes. pnpm is intentionally excluded.
- jira-cli was dropped: no longer installed or used. forgejo-cli replaces it for the self-hosted Forgejo workflow.
- git-cliff generates changelogs from Conventional Commits.
- Docker Desktop and OrbStack were replaced by colima + the docker CLI + docker-compose (free, scriptable, no licence).
- Start the VM with `colima start`; the docker CLI then works unchanged.
- Chrome, Chrome Canary, and Vivaldi all stay available because they each cover a different browser role during setup and testing.
- Comet (Perplexity's AI browser) is the newest addition and is in daily use.
- DuckDuckGo is the search-first companion.
- Antigravity is part of the current AI toolchain.
- Local-first: Ollama and LM Studio serve models, llama.cpp is the raw runtime, whisper.cpp and WhisperKit do speech-to-text, llmfit checks what fits the hardware.
- antigravity-cli replaces gemini-cli, which Homebrew has deprecated as unsupported upstream (disabled 2026-12-18).
- rtk is a CLI proxy that trims LLM token use; herdr, hive-app, supacode and t3-code manage parallel coding agents; codexbar shows Codex/Claude usage in the menu bar.
- Meetily records and transcribes meetings locally.
- OpenTofu is used instead of Terraform.
- oci-cli and gcloud-cli cover Oracle Cloud and Google Cloud; googleworkspace-cli drives Drive, Gmail and Calendar from scripts.
- Xcode and the Apple Developer app come from the Mac App Store (mas), not Homebrew.
- Optional on a minimal machine; install when an app build is needed.
- gitleaks scans repos for secrets before commit; syft builds SBOMs and grype scans them for CVEs.
- ykman manages YubiKeys. john-jumbo is installed but deliberately left out of the rebuild (one-off recovery tool).
- Little Snitch was dropped: it is not installed any more.
- Keyboard Maestro replaces Alfred, Raycast, and standalone clipboard managers.
- Keyboard Maestro and Rectangle Pro still require paid licenses after install.
- BetterDisplay stays because external monitor scaling and brightness control keep coming up.
- MailMate beta is the default on Apple Silicon because the stable cask currently requires Rosetta 2.
- Slack, Discord and Telegram stay in productivity because they are part of the day-to-day communications path.
- KeePassXC moved to the Security group.
- Typora and MarkEdit are the Markdown editors; Zotero holds research references; Anki is for spaced repetition.
- LibreOffice is the non-Microsoft fallback for office files.
- Word and Excel come from the Mac App Store (mas) rather than the microsoft-office cask; the machine runs the App Store builds.
- Windows App (mas 1295203466) replaces the microsoft-remote-desktop cask, which no longer exists in Homebrew.
- Dropped: microsoft-office, microsoft-outlook and onedrive casks (not installed; Outlook and OneDrive are no longer used).
- Vivaldi can still be the main browser even when Edge is installed for compatibility work and Microsoft account flows.
- Skim is the fast lightweight reader. Acrobat Reader covers the Adobe-heavy edge cases.
- qpdf, poppler and tesseract handle splitting, text extraction and OCR; weasyprint renders HTML/Markdown to PDF.
- PDF Expert was dropped: not installed; Skim plus Acrobat cover annotation.
- If Time Machine to the TrueNAS or NFS target already gives a complete backup and clean restore path, this group is all you need.
- Kopia and KopiaUI were dropped: not installed. Replication is handled server-side (ZFS) and with rclone.
- Shottr is installed directly from its website on the current machine; the cask is the repeatable path.
- Kap was dropped: not installed; screen recording uses macOS built-ins.
- BlackHole 2ch is the virtual audio device for routing and recording system audio.
- Useful when the Mac is doubling as a support or network box.
- The current Homebrew cask token is tailscale-app, not tailscale. The machine runs Tailscale.app installed outside Homebrew.
- Dropped: telnet, lftp, ipmitool, net-snmp, openssl (a dependency; macOS and Homebrew already provide it), little-snitch and rustdesk (none installed any more).
- Alfred, Raycast, `pnpm`, Dropover, iBar, Whimsical, and Notion are intentionally excluded.
