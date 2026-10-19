#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
firewall=$(DRY_RUN=1 POLICY_FILE="$ROOT/config/firewall/policy.env.example" bash "$ROOT/scripts/apply-firewall.sh")
grep -q '^ufw allow 22/tcp$' <<< "$firewall"
! grep -q 'ufw --force reset' <<< "$firewall"
grep -q '^ufw default deny incoming$' <<< "$firewall"
grep -q '^ufw default allow outgoing$' <<< "$firewall"
grep -q '^ufw --force enable$' <<< "$firewall"
tailscale=$(DRY_RUN=1 bash "$ROOT/scripts/configure-tailscale-exit-node.sh")
grep -q 'forwarding' <<< "$tailscale"
grep -q 'tailscale0' <<< "$tailscale"
bash -n "$ROOT/scripts/apply-firewall.sh"
bash -n "$ROOT/scripts/install-ssh-hardening.sh"
bash -n "$ROOT/scripts/configure-tailscale-exit-node.sh"
printf '%s\n' 'test-security-policy: passed'
