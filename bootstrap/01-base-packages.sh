#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CONFIG_FILE=${CONFIG_FILE:-"$ROOT/config/packages.env"}
DRY_RUN=${DRY_RUN:-0}

if [[ ! -f "$CONFIG_FILE" ]]; then
  if [[ -f "$ROOT/config/packages.env.example" ]]; then
    printf 'bootstrap: missing %s\n' "$CONFIG_FILE" >&2
    printf 'bootstrap: create it from config/packages.env.example; the example is not used automatically\n' >&2
  else
    printf 'bootstrap: package configuration not found: %s\n' "$CONFIG_FILE" >&2
  fi
  exit 1
fi

[[ "$(id -u)" == 0 || "$DRY_RUN" == 1 ]] || {
  printf 'bootstrap: root is required\n' >&2
  exit 1
}
[[ -f /etc/debian_version ]] || {
  printf 'bootstrap: Debian-based system required (/etc/debian_version missing)\n' >&2
  exit 1
}

# shellcheck disable=SC1090
source "$CONFIG_FILE"

packages=()
declare -A seen=()
add_group() {
  local group_name=$1 group_value=$2 package
  while IFS= read -r package; do
    [[ -z "$package" ]] && continue
    [[ "$package" =~ ^[a-z0-9][a-z0-9+.-]*$ ]] || {
      printf 'bootstrap: invalid package name in %s: %s\n' "$group_name" "$package" >&2
      exit 1
    }
    if [[ -z "${seen[$package]+x}" ]]; then
      seen[$package]=1
      packages+=("$package")
    fi
  done <<< "$group_value"
}

add_group BASE_PACKAGES "${BASE_PACKAGES:-}"
add_group SHELL_PACKAGES "${SHELL_PACKAGES:-}"
add_group SYSTEM_DEBUG_PACKAGES "${SYSTEM_DEBUG_PACKAGES:-}"
add_group NETWORK_DEBUG_PACKAGES "${NETWORK_DEBUG_PACKAGES:-}"
add_group CONTAINER_SUPPORT_PACKAGES "${CONTAINER_SUPPORT_PACKAGES:-}"

((${#packages[@]} > 0)) || {
  printf 'bootstrap: no packages declared in %s\n' "$CONFIG_FILE" >&2
  exit 1
}

printf 'bootstrap: package profile %s (%d unique packages)\n' "$CONFIG_FILE" "${#packages[@]}"
printf 'bootstrap: packages: %s\n' "${packages[*]}"

if [[ "$DRY_RUN" == 1 ]]; then
  printf '%s\n' 'bootstrap: dry-run; apt was not modified'
  exit 0
fi

printf '%s\n' 'bootstrap: updating apt package index'
apt-get update
printf '%s\n' 'bootstrap: installing declared packages'
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${packages[@]}"
printf '%s\n' 'bootstrap: cleaning apt cache'
apt-get clean

printf '%s\n' 'bootstrap: installed package summary'
dpkg-query -W -f='${binary:Package}\t${Version}\n' "${packages[@]}"
printf '%s\n' 'bootstrap: base package layer complete'
