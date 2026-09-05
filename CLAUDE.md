# CLAUDE.md — setup-a-mac-for-me

**Purpose:**
Opinionated MacBook Pro rebuild guide and Homebrew installer (mac.riera.co.uk). Serves as both a GitHub Pages static site (`docs/`) and a practical toolbox for repeatable Mac setup. Publishes Marc's actual daily stack preferences as a single source of truth in `data/install-groups.json`, then generates all derived artifacts (Brewfiles, docs, search index, copy/paste commands) from that one file.

**What It Does:**
- Maintains install groups and bundles (CLI, dev, apps, etc.) as JSON
- Generates Brewfiles for copy/paste during Mac rebuild
- Publishes a GitHub Pages site with raw Homebrew commands + macOS preferences
- Provides shell utilities: `update-mac` (incremental upgrades with pre-flight checks), `verify-setup.sh` (post-install audit), `apply-macos-defaults.sh` (Dock/Launchpad preferences)
- Validates derived files and links on every commit (GitHub Actions)

**Key Files:**
- `data/install-groups.json` — the single source of truth: install groups, bundles, metadata
- `scripts/generate_brew_artifacts.py` — regenerates `brew/` (Brewfiles, copy/paste) and `docs/assets/install-groups.json`
- `scripts/build_search_index.py` — builds the searchable docs index
- `scripts/check_docs.py` — validates site links and required Pages files
- `scripts/update-mac.sh` — safe incremental upgrade with pre-flight summary, dry-run, per-tool prompts
- `scripts/verify-setup.sh` — verifies installed apps and applied macOS defaults
- `scripts/apply-macos-defaults.sh` — applies Dock/Launchpad preferences from the site
- `docs/` — GitHub Pages site (HTML + JS search)
- `brew/` — generated Brewfiles and command snippets

**How to Run / Test:**

1. **Edit the data file:**
   ```sh
   vim data/install-groups.json
   ```

2. **Regenerate derived files** (Brewfiles, docs asset, search index):
   ```sh
   python3 scripts/generate_brew_artifacts.py
   python3 scripts/build_search_index.py
   python3 scripts/check_docs.py
   ```

3. **Preview the site locally:**
   ```sh
   python3 -m http.server --directory docs 8000
   # open http://127.0.0.1:8000
   ```

4. **Run CI checks (what GitHub Actions runs):**
   ```sh
   python3 scripts/generate_brew_artifacts.py --check    # fail if generated files are stale
   python3 scripts/build_search_index.py --check
   python3 scripts/check_docs.py
   for file in brew/Brewfile.*; do brew bundle list --file "$file"; done
   ```

5. **Copy update-mac helper:**
   ```sh
   cp scripts/update-mac.sh ~/bin/update-mac && chmod +x ~/bin/update-mac
   update-mac --dry-run    # preview what would upgrade
   update-mac --yes        # run straight through
   ```

**Layout:**
```
├── data/install-groups.json           # Source: all groups, bundles, metadata
├── scripts/
│   ├── generate_brew_artifacts.py     # data/ → brew/, docs/assets/
│   ├── build_search_index.py          # Generate search index
│   ├── check_docs.py                  # Validate links and required files
│   ├── update-mac.sh                  # Incremental safe upgrades (Time Machine gated)
│   ├── verify-setup.sh                # Post-install audit
│   └── apply-macos-defaults.sh        # Apply Dock/Launchpad prefs
├── docs/                              # GitHub Pages site (HTML + JS)
│   └── assets/                        # Generated: install-groups.json, search index
├── brew/                              # Generated: Brewfiles + copy/paste
├── .github/workflows/validate.yml     # CI: check generated files up-to-date
└── README.md
```

**Conventions:**
- **Single source of truth:** Always edit `data/install-groups.json`; never hand-edit `brew/` or `docs/assets/install-groups.json`.
- **Regenerate before commit:** After editing JSON, run all three Python scripts before staging. CI enforces this (`--check` flags fail if artifacts are stale).
- **Groups are immutable once bundled:** If you add a new group, update affected bundles in the same JSON commit.
- **Python 3.x minimum:** Scripts assume Python 3.6+, use `pathlib` and standard lib only (no pip deps).
- **macOS + bash/sh:** All shell scripts use `set -u` (undefined variable exit), avoid bashisms where POSIX sh suffices.
- **JSON formatting:** Keep groups/bundles in logical order; the site renders them top-to-bottom.

**Gotchas:**
1. **Stale generated files:** If you edit `data/install-groups.json` and forget to regenerate, CI will fail. Run all three scripts after every JSON edit.
2. **Brewfile format:** Homebrew expects specific syntax (`brew "..."` / `cask "..."`). The generator is strict; if it fails, check for typos in formulae/cask names.
3. **macOS version drift:** Some apps (e.g. Keyboard Maestro, Vivaldi) require specific macOS versions; the JSON has no version constraints, so verify manually or document in notes.
4. **Time Machine gate on update-mac:** The upgrade script refuses to run unless Time Machine has a latest backup and a visible destination. This is intentional (safety), but requires Full Disk Access for Terminal.
5. **GitHub Pages delay:** The site updates on `main` push, but caching may show stale content; hard-refresh the browser (Cmd+Shift+R).
6. **Search index rebuild:** If you add a new HTML page to `docs/`, remember to mention it in `build_search_index.py` or it won't be searchable.

**Git & CI:**
- CI validates on every push and PR to `main`.
- The `validate.yml` workflow checks: (1) generated files are up-to-date, (2) search index exists and is built, (3) docs links and required files exist, (4) Brewfiles parse correctly.
- If CI fails, run the same checks locally before pushing: `generate_brew_artifacts.py --check`, `build_search_index.py --check`, `check_docs.py`.
