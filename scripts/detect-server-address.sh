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
  ipv4_address=$(curl -4 -fsS https://api.ipify.org 2>/dev/null || ip route get 1.1.1.1 | awk '/src/ {print $NF}')
  [[ -n "$ipv4_address" ]] || fail 'no global IPv4 address found'
  [[ "$ipv4_address" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || fail 'invalid IPv4 address format'
  [[ ! "$ipv4_address" =~ ^(10|172\.(1[6-9]|2[0-9]|3[0-1])|192\.168)\. ]] || fail 'private IPv4 address detected'
  printf '%s\n' "$ipv4_address"
  exit 0
fi

if [[ "$SERVER_ADDRESS_MODE" == ipv6 ]]; then
  ipv6_address=$(curl -6 -fsS https://api6.ipify.org 2>/dev/null || ip -6 route get 2606:4700:4700::1111 | awk '/src/ {print $NF}')
  [[ -n "$ipv6_address" ]] || fail 'no global IPv6 address found'
  [[ "$ipv6_address" =~ ^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$ ]] || fail 'invalid IPv6 address format'
  [[ ! "$ipv6_address" =~ ^(fe80|fc00|fd00|fe[cd]) ]] || fail 'private IPv6 address detected'
  printf '%s\n' "$ipv6_address"
  exit 0
fi

# auto mode

ipv4_address=$(curl -4 -fsS https://api.ipify.org 2>/dev/null || ip route get 1.1.1.1 | awk '/src/ {print $NF}')
ipv6_address=$(curl -6 -fsS https://api6.ipify.org 2>/dev/null || ip -6 route get 2606:4700:4700::1111 | awk '/src/ {print $NF}')

if [[ "$SERVER_ADDRESS_PREFERENCE" == ipv4 ]]; then
  if [[ -n "$ipv4_address" ]]; then
    [[ "$ipv4_address" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || fail 'invalid IPv4 address format'
    [[ ! "$ipv4_address" =~ ^(10|172\.(1[6-9]|2[0-9]|3[0-1])|192\.168)\. ]] || fail 'private IPv4 address detected'
    printf '%s\n' "$ipv4_address"
    exit 0
  fi
fi

if [[ "$SERVER_ADDRESS_PREFERENCE" == ipv6 ]]; then
  if [[ -n "$ipv6_address" ]]; then
    [[ "$ipv6_address" =~ ^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$ ]] || fail 'invalid IPv6 address format'
    [[ ! "$ipv6_address" =~ ^(fe80|fc00|fd00|fe[cd]) ]] || fail 'private IPv6 address detected'
    printf '%s\n' "$ipv6_address"
    exit 0
  fi
fi

# auto preference

if [[ -n "$ipv4_address" ]]; then
  [[ "$ipv4_address" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || fail 'invalid IPv4 address format'
  [[ ! "$ipv4_address" =~ ^(10|172\.(1[6-9]|2[0-9]|3[0-1])|192\.168)\. ]] || fail 'private IPv4 address detected'
  printf '%s\n' "$ipv4_address"
  exit 0
fi

if [[ -n "$ipv6_address" ]]; then
  [[ "$ipv6_address" =~ ^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$ ]] || fail 'invalid IPv6 address format'
  [[ ! "$ipv6_address" =~ ^(fe80|fc00|fd00|fe[cd]) ]] || fail 'private IPv6 address detected'
  printf '%s\n' "$ipv6_address"
  exit 0
fi

fail 'no public IPv4 or IPv6 address found'