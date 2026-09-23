#!/usr/bin/env bash

# shellcheck disable=SC2034
stage_id="network-rtl8192eu"
stage_description="Build and install RTL8192EU USB WiFi driver (TP-Link TL-WN821N) via DKMS"
stage_profiles=("network")

# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/lib/log.sh"
# shellcheck disable=SC1091
source "${BOOTSTRAP_ROOT}/lib/packages.sh"

RTL8192EU_GIT_URL="https://github.com/clnhub/rtl8192eu-linux.git"
RTL8192EU_DKMS_NAME="rtl8192eu"
RTL8192EU_DKMS_VERSION="1.0"
RTL8192EU_SRC_DIR="/usr/src/rtl8192eu-build"
RTL8192EU_DKMS_SRC="/usr/src/${RTL8192EU_DKMS_NAME}-${RTL8192EU_DKMS_VERSION}"
RTL8192EU_MODULE="8192eu"
RTL8192EU_BLACKLIST="/etc/modprobe.d/rtl8xxxu.conf"

ensure_kernel_build_toolchain() {
  apt-get update
  apt-get install -y --no-install-recommends "linux-headers-$(uname -r)"
}

unload_conflicting_drivers() {
  log_info "Unloading conflicting drivers (if loaded)"
  modprobe -r "${RTL8192EU_MODULE}" 2>/dev/null || true
  modprobe -r rtl8xxxu 2>/dev/null || true
}

clone_driver_source() {
  if [[ -d "${RTL8192EU_SRC_DIR}" ]]; then
    rm -rf "${RTL8192EU_SRC_DIR}"
  fi

  log_info "Cloning RTL8192EU driver source"
  git clone --depth 1 "${RTL8192EU_GIT_URL}" "${RTL8192EU_SRC_DIR}"
  if [[ ! -f "${RTL8192EU_SRC_DIR}/dkms.conf" ]]; then
    log_error "Driver repo missing dkms.conf; cannot build via DKMS"
    return 1
  fi
}

install_driver_via_dkms() {
  log_info "Preparing DKMS source tree"
  rm -rf "${RTL8192EU_DKMS_SRC}"
  cp -a "${RTL8192EU_SRC_DIR}/." "${RTL8192EU_DKMS_SRC}"

  log_info "Removing any previous DKMS registration"
  dkms remove -m "${RTL8192EU_DKMS_NAME}" -v "${RTL8192EU_DKMS_VERSION}" --all 2>/dev/null || true

  log_info "Building and installing driver module via DKMS"
  dkms add -m "${RTL8192EU_DKMS_NAME}" -v "${RTL8192EU_DKMS_VERSION}"
  dkms install -m "${RTL8192EU_DKMS_NAME}" -v "${RTL8192EU_DKMS_VERSION}"
  depmod -a
}

blacklist_conflicting_driver() {
  log_info "Blacklisting rtl8xxxu driver"
  install -m 644 \
    "${BOOTSTRAP_ROOT}/files/modprobe.d/rtl8xxxu.conf" \
    "${RTL8192EU_BLACKLIST}"
}

load_driver_module() {
  log_info "Loading RTL8192EU driver module"
  modprobe "${RTL8192EU_MODULE}"
}

warn_if_secure_boot_enabled() {
  if command -v mokutil >/dev/null 2>&1 \
     && mokutil --sb-state 2>/dev/null | grep -qi 'SecureBoot enabled'; then
    log_warn "Secure Boot is enabled; enroll the DKMS key with 'sudo mokutil --import' after a reboot"
  fi
}

stage_apply() {
  PACKAGE_POLICY_FILE="${BOOTSTRAP_ROOT}/files/packages/network-policy.env"
  load_package_policy

  if [[ "${PACKAGE_POLICY_ALLOW_EXTERNAL:-}" != "1" ]]; then
    log_error "network policy must allow external sources (PACKAGE_POLICY_ALLOW_EXTERNAL=1)"
    return 1
  fi

  ensure_apt_packages "${BOOTSTRAP_ROOT}/files/packages/network-apt.txt"
  ensure_kernel_build_toolchain

  clone_driver_source
  unload_conflicting_drivers
  install_driver_via_dkms
  blacklist_conflicting_driver
  load_driver_module
  warn_if_secure_boot_enabled

  rm -rf "${RTL8192EU_SRC_DIR}"
}

stage_verify() {
  PACKAGE_POLICY_FILE="${BOOTSTRAP_ROOT}/files/packages/network-policy.env"
  load_package_policy

  command -v dkms >/dev/null 2>&1 || { log_error "dkms not found"; return 1; }

  if ! dkms status 2>/dev/null | grep -q "^${RTL8192EU_DKMS_NAME}/"; then
    log_error "RTL8192EU driver not registered with DKMS"
    return 1
  fi

  local module_path="/lib/modules/$(uname -r)/updates/dkms/${RTL8192EU_MODULE}.ko"
  [[ -f "${module_path}" ]] || { log_error "DKMS module not built: ${module_path}"; return 1; }

  [[ -f "${RTL8192EU_BLACKLIST}" ]] || { log_error "Driver blacklist not deployed at ${RTL8192EU_BLACKLIST}"; return 1; }

  modinfo "${RTL8192EU_MODULE}" >/dev/null 2>&1 || { log_error "RTL8192EU module not resolvable via modinfo"; return 1; }

  if ! lsmod | grep -qw "${RTL8192EU_MODULE}"; then
    log_warn "RTL8192EU module not currently loaded; it will load when the adapter is present or after reboot"
  fi

  log_info "network-rtl8192eu stage verified"
  return 0
}