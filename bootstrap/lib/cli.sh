#!/usr/bin/env bash

readonly AVAILABLE_PROFILES=(base desktop keyboard network apps tools ctf llm secrets theme)

STATE_FILE="${STATE_FILE:-./.bootstrap/state.json}"
ASSUME_YES="${ASSUME_YES:-false}"
BOOTSTRAP_USER="${BOOTSTRAP_USER:-}"
TARGET_USER="${TARGET_USER:-}"
SELECTED_PROFILES=()
SELECTED_STAGE_IDS=()
NORMALIZED_SELECTED_PROFILES=()

join_by_comma() {
  local IFS=","
  printf '%s' "$*"
}

profile_is_valid() {
  local candidate="$1"
  local profile
  for profile in "${AVAILABLE_PROFILES[@]}"; do
    if [[ "${profile}" == "${candidate}" ]]; then
      return 0
    fi
  done
  return 1
}

normalize_selected_profiles() {
  local profile
  local -A seen=()

  NORMALIZED_SELECTED_PROFILES=()
  for profile in "$@"; do
    [[ -n "${profile}" ]] || continue
    if ! profile_is_valid "${profile}"; then
      log_error "Unknown profile: ${profile}"
      exit 1
    fi
    if [[ -z "${seen[${profile}]+x}" ]]; then
      NORMALIZED_SELECTED_PROFILES+=("${profile}")
      seen["${profile}"]=1
    fi
  done
}

choose_profiles_interactive() {
  local selection
  local profile
  local input
  local -a chosen_profiles=()

  if command -v gum >/dev/null 2>&1; then
    mapfile -t chosen_profiles < <(
      gum choose --no-limit --header "Select bootstrap profiles" "${AVAILABLE_PROFILES[@]}"
    )
  else
    printf 'Select bootstrap profiles (comma-separated: %s): ' \
      "$(join_by_comma "${AVAILABLE_PROFILES[@]}")" >&2
    IFS= read -r input
    IFS=',' read -r -a chosen_profiles <<<"${input}"
    for profile in "${!chosen_profiles[@]}"; do
      selection="${chosen_profiles[${profile}]}"
      selection="${selection#"${selection%%[![:space:]]*}"}"
      selection="${selection%"${selection##*[![:space:]]}"}"
      chosen_profiles[${profile}]="${selection}"
    done
  fi

  normalize_selected_profiles "${chosen_profiles[@]}"
  SELECTED_PROFILES=("${NORMALIZED_SELECTED_PROFILES[@]}")
}

parse_cli_args() {
  SELECTED_PROFILES=()
  SELECTED_STAGE_IDS=()

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --profile)
        [[ "$#" -ge 2 ]] || {
          log_error "--profile requires a value"
          exit 1
        }
        SELECTED_PROFILES+=("$2")
        shift 2
        ;;
      --stage)
        [[ "$#" -ge 2 ]] || {
          log_error "--stage requires a value"
          exit 1
        }
        SELECTED_STAGE_IDS+=("$2")
        shift 2
        ;;
      --state-file)
        [[ "$#" -ge 2 ]] || {
          log_error "--state-file requires a value"
          exit 1
        }
        STATE_FILE="$2"
        shift 2
        ;;
      --yes)
        ASSUME_YES=true
        shift
        ;;
      --bootstrap-user)
        [[ "$#" -ge 2 ]] || {
          log_error "--bootstrap-user requires a value"
          exit 1
        }
        BOOTSTRAP_USER="$2"
        shift 2
        ;;
      --target-user)
        [[ "$#" -ge 2 ]] || {
          log_error "--target-user requires a value"
          exit 1
        }
        TARGET_USER="$2"
        shift 2
        ;;
      *)
        log_error "Unknown argument: $1"
        exit 1
        ;;
    esac
  done
}
