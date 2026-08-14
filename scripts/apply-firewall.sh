#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
POLICY_FILE=${POLICY_FILE:-"$ROOT/config/firewall/policy.env.example"}
DRY_RUN=${DRY_RUN:-0}
[[ -f "$POLICY_FILE" ]] || { printf 'firewall: policy file not found\n' >&2; exit 1; }
set -a
# shellcheck disable=SC1090
source "$POLICY_FILE"
set +a

case "${SSH_ALLOW_FROM:-}" in any) SSH_RULE=(allow "$SSH_PORT"/tcp);; *) SSH_RULE=(allow from "$SSH_ALLOW_FROM" to any port "$SSH_PORT" proto tcp);; esac
case "${VLESS_ALLOW_FROM:-}" in any) VLESS_RULE=(allow "$VLESS_PORT"/tcp);; *) VLESS_RULE=(allow from "$VLESS_ALLOW_FROM" to any port "$VLESS_PORT" proto tcp);; esac
commands=("ufw --force reset" "ufw default deny incoming" "ufw default allow outgoing" "ufw ${SSH_RULE[*]}" "ufw ${VLESS_RULE[*]}")
if [[ "${ALLOW_PUBLIC_SOCKS:-false}" == true ]]; then
  case "${SOCKS_ALLOW_FROM:-}" in any) commands+=("ufw allow ${SOCKS_PORT}/tcp");; *) commands+=("ufw allow from ${SOCKS_ALLOW_FROM} to any port ${SOCKS_PORT} proto tcp");; esac
fi
commands+=("ufw --force enable")

if [[ "$DRY_RUN" == 1 ]]; then
  printf '%s\n' "${commands[@]}"
  exit 0
fi
[[ "$(id -u)" == 0 ]] || { printf 'firewall: root is required\n' >&2; exit 1; }
command -v ufw >/dev/null 2>&1 || { printf 'firewall: ufw is not installed\n' >&2; exit 1; }
for command_line in "${commands[@]}"; do
  # Policy values are validated above and contain no secrets.
  read -r -a argv <<< "$command_line"
  "${argv[@]}" >/dev/null
done
ufw status verbose
