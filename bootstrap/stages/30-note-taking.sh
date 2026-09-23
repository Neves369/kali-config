#!/usr/bin/env bash

# shellcheck disable=SC2034
stage_id="note-taking"
stage_description="Install note-taking applications (Obsidian)"
stage_profiles=("apps")

# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/lib/desktop.sh"
# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/lib/users.sh"

install_obsidian() {
  local target_home="$1"

  apt-get install -y obsidian

  # Deploy default vault
  local vault_dir="${target_home}/notes/obsidian-vault"
  install_user_dir "notes"
  install_user_dir "notes/obsidian-vault"
  if [[ -d "${BOOTSTRAP_ROOT}/files/note-taking/obsidian/default-vault" ]]; then
    cp -r "${BOOTSTRAP_ROOT}/files/note-taking/obsidian/default-vault/." "${vault_dir}/"
    chown -R "${TARGET_USER}:${TARGET_USER}" "${vault_dir}"
  fi
}

stage_apply() {
  load_or_prompt_target_user >/dev/null

  local target_home
  target_home="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"

  local -a choices=()

  if command -v gum >/dev/null 2>&1; then
    mapfile -t choices < <(
      gum choose --no-limit --header "Select note-taking apps to install" "obsidian"
    )
  else
    printf 'Select note-taking apps (comma-separated: obsidian): ' >&2
    local input
    IFS= read -r input
    IFS=',' read -r -a choices <<<"${input}"
  fi

  local choice
  for choice in "${choices[@]}"; do
    choice="${choice#"${choice%%[![:space:]]*}"}"
    choice="${choice%"${choice##*[![:space:]]}"}"
    case "${choice}" in
      obsidian) install_obsidian "${target_home}" ;;
    esac
  done
}

stage_verify() {
  # At least one note-taking app should be available
  local found=false
  command -v obsidian >/dev/null 2>&1 && found=true

  if [[ "${found}" != "true" ]]; then
    log_warn "No note-taking applications installed (user may have selected none)"
  fi

  log_info "note-taking stage verified"
  return 0
}
