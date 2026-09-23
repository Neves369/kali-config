#!/usr/bin/env bash

# shellcheck disable=SC2034
stage_id="desktop-common-software"
stage_description="Install common desktop applications (audacity, gimp, podman, localsend)"
stage_profiles=("desktop")

# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/lib/packages.sh"
# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/lib/users.sh"

ensure_subuid_subgid() {
  local username="$1"
  local uid gid

  uid="$(id -u "${username}")"
  gid="$(id -g "${username}")"

  if ! grep -q "^${username}:" /etc/subuid 2>/dev/null; then
    log_info "Adding subuid range for ${username}"
    usermod --add-subuids 100000-165535 "${username}" 2>/dev/null || \
      printf '%s:%s:%s\n' "${username}" "100000" "65536" >> /etc/subuid
  fi

  if ! grep -q "^${username}:" /etc/subgid 2>/dev/null; then
    log_info "Adding subgid range for ${username}"
    usermod --add-subgids 100000-165535 "${username}" 2>/dev/null || \
      printf '%s:%s:%s\n' "${username}" "100000" "65536" >> /etc/subgid
  fi
}

stage_apply() {
  load_or_prompt_target_user >/dev/null

  PACKAGE_POLICY_FILE="${BOOTSTRAP_ROOT}/files/packages/desktop-common-policy.env"
  load_package_policy

  ensure_apt_packages "${BOOTSTRAP_ROOT}/files/packages/desktop-common-apt.txt"

  # Rootless podman support
  ensure_subuid_subgid "${TARGET_USER}"

  # Install LocalSend via Flatpak
  if command -v flatpak >/dev/null 2>&1; then
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo >/dev/null 2>&1 || true
    if ! flatpak list --app 2>/dev/null | grep -q 'org.localsend.localsend_app'; then
      log_info "Installing LocalSend via Flatpak"
      flatpak install -y flathub org.localsend.localsend_app || log_warn "LocalSend Flatpak install failed"
    fi
  fi
}

stage_verify() {
  load_or_prompt_target_user >/dev/null

  command -v audacity >/dev/null 2>&1 || { log_error "audacity not found"; return 1; }
  command -v gimp >/dev/null 2>&1 || { log_error "gimp not found"; return 1; }
  command -v podman >/dev/null 2>&1 || { log_error "podman not found"; return 1; }
  grep -q "^${TARGET_USER}:" /etc/subuid || { log_error "subuid not configured for ${TARGET_USER}"; return 1; }
  grep -q "^${TARGET_USER}:" /etc/subgid || { log_error "subgid not configured for ${TARGET_USER}"; return 1; }

  log_info "desktop-common-software stage verified"
  return 0
}
