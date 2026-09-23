# AGENTS.md — kalidots

Context for AI agents working in this repository.

## What this project is

A modular, resumable Kali Linux bootstrap system. It installs packages, creates a primary user, deploys a desktop environment and dotfiles, imports secrets, and configures LLM tooling. Everything runs as root and is orchestrated by a stage runner with JSON state tracking.

## Repository layout

```
bootstrap/
  bin/kali-bootstrap        Entry point. Sources libs, parses CLI, runs stages.
  lib/                      Shared shell libraries (see "Libraries" below).
  stages/                   Auto-discovered stage scripts (NN-name.sh).
  files/                    Static config files, package manifests, policy files.
tests/bootstrap/lib/        Unit tests for library functions.
```

## Architecture concepts

### Profiles and stages

There are ten **profiles**: `base`, `desktop`, `keyboard`, `network`, `apps`, `tools`, `ctf`, `secrets`, `llm`, `theme`. Each **stage** declares which profiles it belongs to via a `stage_profiles` array. The runner discovers all `bootstrap/stages/*.sh` files alphabetically, matches them against selected profiles, and executes them in order. The `keyboard` profile is separate from `desktop` — it covers system-level/low-level keyboard configuration (e.g. Kanata), not desktop-environment-specific keybindings. The `network` profile covers system-level drivers and hardware configuration for network adapters (e.g. the RTL8192EU USB WiFi driver). The `ctf` profile is for platform-specific CTF tooling that is not part of the general `tools` profile. The `theme` profile is independent from `desktop` — it overlays color schemes on top of already-deployed desktop configs.

Stage `21-bootstrap-user-cleanup` has no profile — it only runs when explicitly requested via `--stage bootstrap-user-cleanup`.

### Stage contract

Every stage file **must** declare these top-level variables and functions:

```bash
stage_id="my-stage"                          # Unique identifier
stage_description="What this stage does"     # Human-readable
stage_profiles=("profile1" "profile2")       # Which profiles trigger this stage

stage_apply() {
  # Mutating work: install packages, deploy files, create users, etc.
}

stage_verify() {
  # Non-mutating checks: command -v, file existence, permissions, group membership.
  # Return 0 on success, 1 on failure.
}
```

Stages are sourced into the runner's shell. They can use any function from the libraries loaded by the runner (`log.sh`, `state.sh`) and should source additional libraries they need from `${BOOTSTRAP_ROOT}/lib/`.

### State machine

Each stage transitions through: `pending` → `applying` → `verifying` → `verified` (or `verify_failed`). State is persisted to `.bootstrap/state.json`. On re-run, `verified` stages are skipped. Stages stuck in `verifying` or `verify_failed` get their `stage_verify` re-checked before re-applying.

### Package policy

Each profile has a policy env file (`bootstrap/files/packages/*-policy.env`) that controls:
- `PACKAGE_POLICY_PLATFORM` — must be `kali`
- `PACKAGE_POLICY_ALLOW_EXTERNAL` — `0` (apt only) or `1` (external sources permitted)
- `PACKAGE_POLICY_EXTERNAL_EXCEPTIONS` — CSV of allowed external tools (e.g., `starship,kanata,rustup-toolchain`)

Stages that install from external sources (curl, GitHub releases, `go install`) must only do so when the loaded policy permits it.

## Libraries

| File | Purpose | Key functions |
|------|---------|--------------|
| `lib/log.sh` | Logging | `log_info`, `log_warn`, `log_error` |
| `lib/cli.sh` | CLI parsing | `parse_cli_args`, `choose_profiles_interactive`, `normalize_selected_profiles` |
| `lib/state.sh` | JSON state (requires jq) | `state_init`, `state_get_value`, `state_set_value`, `state_mark_stage`, `state_get_stage_status` |
| `lib/runner.sh` | Stage discovery and execution | `load_stage_registry`, `run_selected_stages`, `filter_stages_for_profiles` |
| `lib/packages.sh` | Apt package management | `ensure_apt_packages`, `load_package_policy`, `apt_package_installed` |
| `lib/users.sh` | User management | `load_or_prompt_target_user`, `create_target_user`, `ensure_target_groups`, `prompt_with_fallback` |
| `lib/desktop.sh` | File deployment to user home | `install_user_file`, `install_user_dir` |
| `lib/secrets.sh` | SSH/KeePassXC import | `import_ssh_directory`, `import_keepassxc_database`, `normalize_ssh_permissions` |
| `lib/llm.sh` | LLM tool manifest | `load_llm_tool_manifest`, `deploy_llm_auth_artifacts`, `llm_assert_manifest_contract` |

## Key globals

These are set by `cli.sh` and used throughout:

- `BOOTSTRAP_ROOT` — absolute path to `bootstrap/` directory
- `SELECTED_PROFILES` — array of active profile names
- `SELECTED_STAGE_IDS` — array of explicitly requested stage IDs (overrides profile matching)
- `TARGET_USER` — the primary user being configured (prompted or from env/state)
- `BOOTSTRAP_USER` — the user running the installer
- `STATE_FILE` — path to `.bootstrap/state.json`
- `ASSUME_YES` — skip confirmation prompts when `true`

## Conventions to follow

### Shell style

- All scripts use `#!/usr/bin/env bash` and `set -euo pipefail` (stages inherit this from the runner).
- Use `log_info`, `log_warn`, `log_error` for output — never raw `echo` for user-facing messages.
- Whitespace trimming uses the POSIX parameter expansion pattern: `${var#"${var%%[![:space:]]*}"}` (see `trim_whitespace` in `users.sh`).
- File deployment uses `install -D -m MODE -o OWNER -g GROUP SRC DEST` for atomic ownership + permissions.
- Config file paths under the user's home use `install_user_file` from `desktop.sh`.
- User-scoped Go installs use `GOPATH="$HOME/.local/share/go"` and place binaries in `"$HOME/.local/share/go/bin"`. When verifying or invoking Go-installed tools for `TARGET_USER`, include that bin directory in `PATH`.
- When using `runuser -u "${TARGET_USER}"` for user-scoped commands, do not inherit the repository working directory. Run from the target user's home (for example `cd "$HOME"` first) so users without access to the bootstrap checkout do not hit `chdir ... permission denied`.

### Keyboard vs Desktop profile boundary

The `keyboard` profile covers system-level/low-level keyboard configuration (Kanata, key remapping, input device setup). Desktop-environment-specific keybindings (i3 bindsym, Hyprland binds) belong in `desktop`. When adding new keyboard-related stages, use the `keyboard` profile and the 29 numbering range. The `apps` profile covers optional application installs (note-taking).

### Network profile

The `network` profile covers low-level network adapter drivers and hardware configuration, mirroring the `keyboard` profile pattern. Driver stages use the 24 numbering range (e.g., `24-network-rtl8192eu.sh`). Kernel module builds use DKMS so the module survives kernel upgrades, and static disablement configs (e.g., `/etc/modprobe.d/*.conf`) are deployed from `bootstrap/files/modprobe.d/`. Dynamic dependencies (e.g., `linux-headers-$(uname -r)`) are installed inline with `apt-get install -y --no-install-recommends`; static build deps go in `files/packages/network-apt.txt`.

### Theme profile

The `theme` profile uses the 200-series numbering range. Each theme is a separate stage (e.g., `200-theme-pink-rot.sh`, `201-theme-next.sh`). Theme stages overlay color configs on top of desktop-deployed files — they use `sed` for i3 config color variables and `install_user_file` for full replacements of smaller configs. Theme config files live under `bootstrap/files/theme/<theme-name>/`. The theme profile requires the `desktop` profile to have been run first (configs must already exist to overlay).

### Adding a new stage

1. Create `bootstrap/stages/NN-name.sh` where `NN` determines execution order.
2. Declare `stage_id`, `stage_description`, `stage_profiles`.
3. Implement `stage_apply` and `stage_verify`.
4. Source any needed libraries from `${BOOTSTRAP_ROOT}/lib/`.
5. If the stage needs the target user, call `load_or_prompt_target_user >/dev/null` at the start of `stage_apply`.
6. If the stage installs apt packages, put them in `bootstrap/files/packages/PROFILE-apt.txt` and use `ensure_apt_packages`.
7. If the stage needs external downloads, ensure the profile's policy file has `PACKAGE_POLICY_ALLOW_EXTERNAL=1` and the tool is listed in `PACKAGE_POLICY_EXTERNAL_EXCEPTIONS`.

### Adding a new package

Append the package name to the appropriate `bootstrap/files/packages/*-apt.txt` manifest. One package per line, `#` comments allowed. The `ensure_apt_packages` function handles idempotent installation.

### Verification patterns

`stage_verify` should only read state, never mutate. Common patterns:
- `command -v BINARY >/dev/null 2>&1` — check binary availability
- `[[ -f PATH ]]` — check file exists
- `stat -c %a PATH` / `stat -c %U PATH` — check permissions/ownership
- `id -nG USER | grep -qw GROUP` — check group membership
- `getent passwd USER | cut -d: -f7` — check login shell
- `systemctl is-enabled SERVICE` — check systemd unit

### Config file deployment

Static config files live under `bootstrap/files/`. The path structure mirrors the destination:
- `files/desktop/i3/config` → `~/.config/i3/config`
- `files/desktop/i3/scripts/*.sh` → `~/.config/i3/scripts/*.sh` (mode 755)
- `files/desktop/alacritty/alacritty.toml` → `~/.config/alacritty/alacritty.toml`
- `files/theme/pink-rot/*` → themed overlays deployed by `200-theme-pink-rot.sh`

Some configs use placeholder substitution (e.g., `__TARGET_HOME__` replaced with the actual home path at deploy time via `sed`). When adding new configs, check whether the stage does substitution.

### Bashrc drop-ins

Shell initialization uses a drop-in directory pattern. Stages append a sourcing block to `~/.bashrc` (idempotently checked with `grep`) and place individual scripts in `~/.bashrc.d/NN-name.sh`. The number prefix controls load order.

### Update manifest pattern

Tools installed from GitHub releases (AppImages, static binaries, .debs) register in `~/.config/kalidots/update-manifest.json`. Each entry has `name`, `source` (e.g., `github:owner/repo`), `install_method`, `binary_path`, and `current_version`. The update manager script queries GitHub API to detect outdated tools.

### Podman container pattern

Tools too complex to install natively (e.g., reconftw) use a podman container with a shell wrapper in `/usr/local/bin/`. The wrapper uses `exec podman run --rm -it -v "$(pwd):/<mount>" IMAGE "$@"`.

### Direct binary install pattern

GitHub-hosted binaries are downloaded from releases, optionally checksum-verified, and placed directly in `/usr/local/bin/`. The version is registered in the update manifest. Examples: opengrep, tailscale.

### PyPI install via mise pattern

Tools that benefit from pip install (e.g., qutebrowser) use mise-managed Python to avoid polluting the system Python. A system wrapper in `/usr/local/bin/` sets PATH to include mise shims. A `.desktop` file is created for desktop integration.

## Tests

Tests live in `tests/bootstrap/lib/` and are plain bash scripts. Run them directly:

```bash
bash tests/bootstrap/lib/users_prompt_fallback_test.sh
bash tests/bootstrap/lib/secrets_import_test.sh
```

Test conventions:
- Each test file sources the library it tests and defines `assert_eq`, `assert_contains`, `assert_nonzero` helpers.
- Tests mock functions by redefining them (e.g., override `gum`, `prompt_with_fallback`, `state_get_value`).
- Temp directories are cleaned up via `trap ... EXIT`.
- Tests print `PASS` / `FAIL` and exit 0/1.

## Things to be careful about

- **Runs as root**: Every stage runs with root privileges. File ownership must be explicitly set to `TARGET_USER` when deploying to the user's home.
- **State file is the source of truth for resumability**: Don't manually edit `.bootstrap/state.json` unless debugging. The runner uses it to skip verified stages.
- **LLM manifest contract**: The `llm_assert_manifest_contract` function enforces that all three LLM tools (codex, claude, gemini) remain `manual` method with `not-installed-by-bootstrap`. Do not change this.
- **No secrets in state**: API keys, passwords, and credentials must never be written to `state.json` or committed. The LLM and secrets stages deploy templates and documentation only.
- **Telemetry registry**: Every tool in all `*-apt.txt` manifests must have a corresponding entry in `privacy/telemetry-registry.env`. Stage `52-tools-privacy` enforces this. See the "Telemetry tracking" section below for packages with active countermeasures.
- **System groups**: The `uinput` group must have GID < 1000 (system group) for udev rules to work. Use `groupadd --system`.

## Telemetry tracking

Every installed tool must have a telemetry posture documented in `bootstrap/files/privacy/telemetry-registry.env`. The table below tracks packages that **actively collect telemetry** and the countermeasures applied. When adding new tools, always check for telemetry and update both the registry and this table.

### Packages with active countermeasures

| Package | What it collects | Countermeasure | Where applied |
|---------|-----------------|----------------|---------------|
| **Go** | Usage and crash reporting | `go telemetry off` command | Stage `52-tools-privacy.sh` runs it for target user |
| **mise** | Anonymous download stats sent to `mise-versions.jdx.dev` after tool installs | `MISE_USE_VERSIONS_HOST=0` env var | `bashrc.d/50-mise.sh` drop-in; also passed during stage `40-repos-external.sh` install commands |
| **Firefox ESR** | Mozilla telemetry (usage, crash, technical data) | Disabled via enterprise policy | Registry entry: `mozilla_telemetry_disabled_via_enterprise_policy` |

### Packages with unknown/unresolved telemetry posture

These are flagged in the registry and logged as warnings by stage `52-tools-privacy`:

| Package | Concern |
|---------|---------|
| **Metasploit** | Communicates with Rapid7 update servers |
| **Burp Suite** | Proprietary update checks |
| **ZAProxy** | Update check posture needs review |
| **NetExec** | Posture needs review |
| **BloodHound** | Electron app update posture needs review |
| **Neo4j** | Server usage metrics posture needs review |
| **Proxychains4** | Posture not explicitly documented |
| **Remmina** | Posture needs review |
