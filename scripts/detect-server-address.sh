#!/usr/bin/env bash
set -euo pipefail

SERVER_ADDRESS_MODE=${SERVER_ADDRESS_MODE:-auto}
SERVER_ADDRESS_PREFERENCE=${SERVER_ADDRESS_PREFERENCE:-ipv4}

fail() {
  printf 'detect-server-address: %s\n' "$1" >&2
  exit 1
}

[[ "$SERVER_ADDRESS_MODE" =~ ^(auto|ipv4|ipv6)$ ]] || fail 'SERVER_ADDRESS_MODE must be auto, ipv4, or ipv6'
[[ "$SERVER_ADDRESS_PREFERENCE" =~ ^(ipv4|ipv6|auto)$ ]] || fail 'SERVER_ADDRESS_PREFERENCE must be ipv4, ipv6, or auto'

get_ipv4() {
  local address=''
  address=$(curl -4 -fsS https://api.ipify.org 2>/dev/null) || true
  if [[ -z "$address" ]]; then
    address=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '/src/ {print $NF; exit}') || true
  fi
  printf '%s\n' "$address"
}

get_ipv6() {
  local address=''
  address=$(curl -6 -fsS https://api6.ipify.org 2>/dev/null) || true
  if [[ -z "$address" ]]; then
    address=$(ip -6 route get 2606:4700:4700::1111 2>/dev/null | awk '/src/ {print $NF; exit}') || true
  fi
  printf '%s\n' "$address"
}

validate_ipv4() {
  local address=$1
  [[ "$address" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
  [[ ! "$address" =~ ^(10|172\.(1[6-9]|2[0-9]|3[0-1])|192\.168)\. ]] || return 1
}

validate_ipv6() {
  local address=$1
  [[ "$address" =~ : ]] || return 1
  [[ ! "$address" =~ ^(fe80|fc00|fd00|fe[cd]) ]] || return 1
}

if [[ "$SERVER_ADDRESS_MODE" == ipv4 ]]; then
  ipv4_address=$(get_ipv4)
  [[ -n "$ipv4_address" ]] || fail 'no global IPv4 address found'
  validate_ipv4 "$ipv4_address" || fail 'invalid or private IPv4 address detected'
  printf '%s\n' "$ipv4_address"
  exit 0
fi

if [[ "$SERVER_ADDRESS_MODE" == ipv6 ]]; then
  ipv6_address=$(get_ipv6)
  [[ -n "$ipv6_address" ]] || fail 'no global IPv6 address found'
  validate_ipv6 "$ipv6_address" || fail 'invalid or private IPv6 address detected'
  printf '%s\n' "$ipv6_address"
  exit 0
fi

# auto mode: probe address families independently; an unavailable family must
# not abort discovery when the preferred family is healthy.
ipv4_address=$(get_ipv4)
ipv6_address=$(get_ipv6)

if [[ "$SERVER_ADDRESS_PREFERENCE" == ipv4 ]]; then
  if [[ -n "$ipv4_address" ]] && validate_ipv4 "$ipv4_address"; then
    printf '%s\n' "$ipv4_address"
    exit 0
  fi
fi

if [[ "$SERVER_ADDRESS_PREFERENCE" == ipv6 ]]; then
  if [[ -n "$ipv6_address" ]] && validate_ipv6 "$ipv6_address"; then
    printf '%s\n' "$ipv6_address"
    exit 0
  fi
fi

if [[ -n "$ipv4_address" ]] && validate_ipv4 "$ipv4_address"; then
  printf '%s\n' "$ipv4_address"
  exit 0
fi

if [[ -n "$ipv6_address" ]] && validate_ipv6 "$ipv6_address"; then
  printf '%s\n' "$ipv6_address"
  exit 0
fi

fail 'no public IPv4 or IPv6 address found'
