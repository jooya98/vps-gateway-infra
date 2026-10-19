#!/usr/bin/env bash
set -euo pipefail
DRY_RUN=${DRY_RUN:-0}
fail(){ printf 'tailscale-exit-node: %s\n' "$1" >&2; exit 1; }
[[ $(id -u) == 0 || "$DRY_RUN" == 1 ]] || fail 'root is required'
if [[ "$DRY_RUN" == 1 ]]; then
  printf '%s\n' 'install Tailscale from the official Tailscale installer if absent'
  printf '%s\n' 'enable IPv4 and IPv6 forwarding through /etc/sysctl.d/99-tailscale-exit-node.conf'
  printf '%s\n' 'add UFW forwarding from tailscale0 to the default-route interface'
  printf '%s\n' 'enable tailscaled and advertise this machine as an exit node'
  exit 0
fi
command -v curl >/dev/null || fail 'curl is required'
command -v ip >/dev/null || fail 'iproute2 is required'
WAN_IF=$(ip -4 route show default | awk 'NR==1 {print $5}')
[[ -n "$WAN_IF" ]] || fail 'could not detect the default IPv4 route interface'
if ! command -v tailscale >/dev/null 2>&1; then
  tmp=$(mktemp)
  trap 'rm -f "$tmp"' EXIT
  curl -fsSL https://tailscale.com/install.sh -o "$tmp"
  bash "$tmp"
fi
install -d -m 0755 /etc/sysctl.d
cat > /etc/sysctl.d/99-tailscale-exit-node.conf <<'EOF'
# Required for Tailscale exit-node forwarding.
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sysctl --system >/dev/null
systemctl enable --now tailscaled
if command -v ufw >/dev/null 2>&1; then
  ufw route allow in on tailscale0 out on "$WAN_IF" >/dev/null
fi
if tailscale status --json 2>/dev/null | grep -Eq '"BackendState"[[:space:]]*:[[:space:]]*"Running"'; then
  tailscale set --advertise-exit-node
  tailscale up
else
  tailscale up --advertise-exit-node
fi
printf '%s\n' 'tailscale-exit-node: configured; authenticate if prompted and approve the exit-node capability in the Tailscale admin console.'
