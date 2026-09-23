# kalidots

A modular, resumable bootstrap system for Kali Linux workstations. Installs packages, configures a desktop environment with i3, deploys dotfiles, manages browsers and note-taking tools, imports secrets, and sets up LLM tooling — all driven by a profile-based stage runner with built-in state tracking, verification, and a centralized update manager.

## Quick Start

```bash
# Interactive — prompts for profiles, username, passwords, etc.
sudo ./bootstrap/bin/kali-bootstrap

# Non-interactive — base + desktop for user "hacker"
sudo TARGET_USER=hacker ./bootstrap/bin/kali-bootstrap \
  --profile base --profile desktop --yes

# Resume after failure — skips already-verified stages
sudo ./bootstrap/bin/kali-bootstrap --profile base --profile tools
```

## Profiles

Profiles group stages by purpose. Select one or more at runtime.

| Profile | What it does |
|---------|-------------|
| **base** | Bootstrap prerequisites (jq, gum, git, etc.) and target user creation |
| **desktop** | i3 window manager, Rofi, Alacritty, tmux, Firefox, qutebrowser, common software |
| **keyboard** | Kanata keyboard remapper with systemd service, udev rules, optional enthium layout |
| **network** | RTL8192EU USB WiFi driver (TP-Link TL-WN821N) built via DKMS with conflicting driver blacklist |
| **apps** | Optional application installs — note-taking (Obsidian) |
| **tools** | 60+ security packages, language runtimes, mise, external repos (Netbird, Tailscale), telemetry opt-outs |
| **ctf** | Platform-specific CTF tooling (HTB toolkit) |
| **secrets** | SSH directory and KeePassXC database import with permission enforcement |
| **llm** | LLM auth documentation and config templates (Codex, Claude, Gemini) |
| **theme** | Color scheme overlays for desktop apps (requires desktop profile first) |

## Stages

Each stage declares which profiles it belongs to, a `stage_apply` function, and a `stage_verify` function. The runner discovers stages from `bootstrap/stages/*.sh` in alphabetical order.

| Stage | Profile | Description |
|-------|---------|-------------|
| `10-system-base` | base | Install jq, gum, sudo, curl, git, shellcheck |
| `20-user-migration` | base | Create target user (UID > 10000), assign groups |
| `21-bootstrap-user-cleanup` | *(explicit only)* | Remove the bootstrap user — requires `--stage` flag |
| `24-network-rtl8192eu` | network | RTL8192EU WiFi driver (TP-Link TL-WN821N) via DKMS + rtl8xxxu blacklist |
| `25-desktop-i3` | desktop | Deploy i3 config with named workspaces, hjkl bindings, autotiling |
| `26-desktop-apps` | desktop | Rofi, Alacritty, tmux, zsh, shell configs, i3status-rs, update manifest |
| `27-desktop-neovim` | desktop | Neovim + LazyVim starter |
| `28-desktop-common-software` | desktop | Audacity, GIMP, Podman, LocalSend |
| `29-keyboard-kanata` | keyboard | Kanata keyboard remapper with systemd service + udev rules |
| `30-note-taking` | apps | Obsidian (multi-select) |
| `53-browser-firefox` | desktop | Firefox profiles (operator + regular), addons, SecurityBookmarks, enterprise policy |
| `54-browser-qutebrowser` | desktop | qutebrowser via PyPI (mise Python), adblock, system wrapper |
| `40-repos-external` | tools | Mise runtime manager, global node/python, Netbird, Tailscale |
| `50-tools-apt` | tools | 60+ security tool packages, reconftw (container), opengrep, rockyou |
| `51-tools-runtimes` | tools | Rust toolchain, Go tools, pipx, reference repos |
| `52-tools-privacy` | tools | Telemetry opt-outs (Go telemetry, registry enforcement across all manifests) |
| `60-secrets-import` | secrets | SSH keys + KeePassXC vault import with strict permissions |
| `70-llm-tooling` | llm | Deploy auth docs and config templates for LLM tools |
| `150-ctf-htbtoolkit` | ctf | Hack The Box toolkit |
| `200-theme-pink-rot` | theme | Pink-rot color theme for all desktop apps |

## Update Manager

The centralized update manager (`~/.config/i3/scripts/update-manager.sh`) handles:

1. **APT packages** — `apt update && apt upgrade`
2. **Flatpak apps** — KeePassXC, LocalSend, etc.
3. **Manifest-tracked tools** — Queries GitHub API for latest releases of opengrep, Tailscale

The update manifest lives at `~/.config/kalidots/update-manifest.json`. Each tool-installing stage registers its version there.

Access via the Kali menu (Super+Alt+Space > Update) or the i3 keybinding.

## CLI Reference

```
sudo ./bootstrap/bin/kali-bootstrap [OPTIONS]

Options:
  --profile PROFILE       Profile to activate (repeatable: base, desktop, keyboard, network, apps, tools, ctf, llm, secrets, theme)
  --stage STAGE_ID        Run specific stage(s) by ID, overrides profile matching (repeatable)
  --state-file PATH       Custom state file path (default: .bootstrap/state.json)
  --yes                   Skip confirmation prompts
  --bootstrap-user USER   User running the installer
  --target-user USER      Target primary user to create/configure
```

### Environment Variables

| Variable | Purpose |
|----------|---------|
| `TARGET_USER` | Target primary user (prompted if unset) |
| `BOOTSTRAP_USER` | User running installer |
| `ASSUME_YES` | Skip confirmations (`true`/`false`) |
| `STATE_FILE` | State JSON path |
| `SSH_IMPORT_SOURCE` | SSH directory to import |
| `KEEPASSXC_DB_SOURCE` | KeePassXC vault path |
| `KEEPASSXC_KEYFILE_SOURCE` | KeePassXC keyfile path |
| `KANATA_LAYOUT_FILE` | Custom Kanata layout file |

## Architecture

### State & Resumability

Every stage run is tracked in `.bootstrap/state.json`. Each stage transitions through:

```
pending -> applying -> verifying -> verified
                          |
                    verify_failed
```

On re-run, verified stages are skipped. Failed stages re-check verification before re-applying.

### Package Policy

Each profile has a policy file (`bootstrap/files/packages/*-policy.env`) controlling:

- **Platform**: Must be `kali`
- **Allow external**: Whether non-apt sources are permitted
- **External exceptions**: Specific tools allowed from external sources

### Desktop Environment

- **Window manager**: i3 with named workspaces, hjkl bindings, autotiling
- **Terminal**: Alacritty + tmux (C-Space prefix)
- **Launcher**: Rofi with Kali tools menu, flattened paths menu, emoji picker
- **Browsers**: Firefox ESR (operator profile + addons), qutebrowser (PyPI)
- **Shell**: Vi-mode, zsh default, bashrc.d drop-in system
- **Keyboard** *(separate `keyboard` profile)*: Kanata remapper via systemd + udev

### Keybinding Highlights

| Binding | Action |
|---------|--------|
| Super+Return | Rofi drun |
| Super+Alt+Space | Kali tools menu |
| Super+O | Notes workspace |
| Super+T | Terminal workspace |
| Super+M | Music workspace |
| Super+Shift+O | Launch Obsidian |
| Super+Ctrl+E | Emoji picker (rofimoji) |
| Super+Alt+E | Paths (terminal) |
| Super+Ctrl+Alt+E | Paths (file explorer) |

## Repository Structure

```
bootstrap/
├── bin/kali-bootstrap          # Entry point
├── lib/                        # Shared libraries
├── stages/                     # Stage scripts (auto-discovered, NN-name.sh)
├── files/
│   ├── packages/               # Apt lists + policy files per profile
│   ├── user/                   # Required groups, migration checklist
│   ├── desktop/                # i3, rofi, alacritty, tmux, qutebrowser, shell configs
│   ├── note-taking/            # Obsidian default vault
│   ├── systemd/                # Kanata service + udev rules
│   ├── tools/                  # Reference repo list
│   ├── secrets/                # Import policy
│   ├── privacy/                # Telemetry registry
│   ├── theme/                  # Theme overlays (pink-rot)
│   └── llm/                    # Tool manifest, auth docs, config templates
└── tests/                      # Unit tests for library functions
```
