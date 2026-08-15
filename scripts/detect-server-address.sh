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

if [[ "$SERVER_ADDRESS_MODE" == ipv4 ]]; then
  ipv4_address=$(ip -4 addr show scope global | awk '/inet / {print $2}' | cut -d/ -f1 | head -1)
  [[ -n "$ipv4_address" ]] || fail 'no global IPv4 address found'
  printf '%s\n' "$ipv4_address"
  exit 0
fi

if [[ "$SERVER_ADDRESS_MODE" == ipv6 ]]; then
  ipv6_address=$(ip -6 addr show scope global | awk '/inet6 / {print $2}' | cut -d/ -f1 | grep -v '^fe80:' | head -1)
  [[ -n "$ipv6_address" ]] || fail 'no global IPv6 address found'
  printf '%s\n' "$ipv6_address"
  exit 0
fi

# auto mode

ipv4_address=$(ip -4 addr show scope global | awk '/inet / {print $2}' | cut -d/ -f1 | head -1)
ipv6_address=$(ip -6 addr show scope global | awk '/inet6 / {print $2}' | cut -d/ -f1 | grep -v '^fe80:' | head -1)

if [[ "$SERVER_ADDRESS_PREFERENCE" == ipv4 ]]; then
  [[ -n "$ipv4_address" ]] || fail 'no global IPv4 address found'
  printf '%s\n' "$ipv4_address"
  exit 0
fi

if [[ "$SERVER_ADDRESS_PREFERENCE" == ipv6 ]]; then
  [[ -n "$ipv6_address" ]] || fail 'no global IPv6 address found'
  printf '%s\n' "$ipv6_address"
  exit 0
fi

# auto preference

if [[ -n "$ipv4_address" ]]; then
  printf '%s\n' "$ipv4_address"
  exit 0
fi

if [[ -n "$ipv6_address" ]]; then
  printf '%s\n' "$ipv6_address"
  exit 0
fi

fail 'no public IPv4 or IPv6 address found'