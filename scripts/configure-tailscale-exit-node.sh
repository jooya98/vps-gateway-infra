#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=${DRY_RUN:-0}
TAILSCALE_EXIT_NODE_STATE_FILE=${TAILSCALE_EXIT_NODE_STATE_FILE:-/etc/vps-gateway/tailscale-exit-node.conf}
fail(){ printf 'tailscale-exit-node: %s\n' "$1" >&2; exit 1; }

[[ $(id -u) == 0 || "$DRY_RUN" == 1 ]] || fail 'root is required'
if [[ "$DRY_RUN" == 1 ]]; then
  printf '%s\n' 'install Tailscale from the official Tailscale installer if absent'
  printf '%s\n' 'enable IPv4 and IPv6 forwarding through /etc/sysctl.d/99-tailscale-exit-node.conf'
  printf '%s\n' 'require UFW to be active after the gateway bootstrap'
  printf '%s\n' 'advertise this machine as an exit node and verify tailscaled is Running'
  printf '%s\n' "record WAN_IF in $TAILSCALE_EXIT_NODE_STATE_FILE"
  printf '%s\n' 'add UFW forwarding from tailscale0 to the default-route interface'
  printf '%s\n' 'managed UFW resets will restore the recorded Tailscale forwarding rule'
  exit 0
fi

command -v curl >/dev/null || fail 'curl is required'
command -v ip >/dev/null || fail 'iproute2 is required'
command -v ufw >/dev/null || fail 'ufw is required; run this after gateway bootstrap'
ufw_status=$(ufw status 2>/dev/null) || fail 'could not read UFW status'
grep -Fxq 'Status: active' <<< "$ufw_status" || fail 'UFW must be active; run this after gateway bootstrap'

WAN_IF=$(ip -4 route show default | awk 'NR==1 {print $5}')
[[ "$WAN_IF" =~ ^[-A-Za-z0-9_.:]{1,15}$ ]] || fail 'could not detect a valid default-route interface'

if ! command -v tailscale >/dev/null 2>&1; then
  tmp=$(mktemp)
  trap 'rm -f "$tmp"' EXIT
  curl -fsSL https://tailscale.com/install.sh -o "$tmp"
  bash "$tmp"
  rm -f "$tmp"
  trap - EXIT
fi

install -d -m 0755 /etc/sysctl.d
cat > /etc/sysctl.d/99-tailscale-exit-node.conf <<'EOF'
# Required for Tailscale exit-node forwarding.
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sysctl --system >/dev/null
systemctl enable --now tailscaled

if tailscale status --json 2>/dev/null | grep -Eq '"BackendState"[[:space:]]*:[[:space:]]*"Running"'; then
  tailscale set --advertise-exit-node
  tailscale up
else
  tailscale up --advertise-exit-node
fi

# A tailscale up invocation may return after printing an authentication URL.
# Do not record the feature as configured until the daemon is connected.
if ! tailscale status --json 2>/dev/null | grep -Eq '"BackendState"[[:space:]]*:[[:space:]]*"Running"'; then
  fail 'Tailscale is not connected yet; finish the authentication URL, then rerun this script'
fi

# Persist intent before adding the UFW rule. If the UFW command fails, a future
# managed firewall application can still reconstruct the required route rule.
state_dir=$(dirname "$TAILSCALE_EXIT_NODE_STATE_FILE")
install -d -m 0755 "$state_dir"
state_tmp=$(mktemp "$state_dir/.tailscale-exit-node.XXXXXX")
printf 'WAN_IF=%s\n' "$WAN_IF" > "$state_tmp"
chown root:root "$state_tmp"
chmod 0600 "$state_tmp"
mv -f "$state_tmp" "$TAILSCALE_EXIT_NODE_STATE_FILE"

ufw route allow in on tailscale0 out on "$WAN_IF" >/dev/null || fail 'could not add UFW forwarding rule; rerun the gateway firewall script to restore it'
printf 'tailscale-exit-node: configured on WAN interface %s; state=%s\n' "$WAN_IF" "$TAILSCALE_EXIT_NODE_STATE_FILE"
printf '%s\n' 'tailscale-exit-node: approve the exit-node capability in the Tailscale admin console, then select this node on each client.'
