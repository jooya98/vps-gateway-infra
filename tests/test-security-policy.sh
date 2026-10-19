#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
firewall=$(DRY_RUN=1 RESET_UFW=1 POLICY_FILE="$ROOT/config/firewall/policy.env.example" bash "$ROOT/scripts/apply-firewall.sh")
grep -q '^ufw --force reset
grep -q '^ufw default deny incoming$' <<< "$firewall"
grep -q '^ufw default allow outgoing$' <<< "$firewall"
grep -q '^ufw --force enable$' <<< "$firewall"
tailscale=$(DRY_RUN=1 bash "$ROOT/scripts/configure-tailscale-exit-node.sh")
grep -q 'forwarding' <<< "$tailscale"
grep -q 'tailscale0' <<< "$tailscale"
grep -q 'SSH_ADMIN_LOGIN_VERIFIED' "$ROOT/scripts/install-ssh-hardening.sh"
grep -q 'restoring previous SSH configuration' "$ROOT/scripts/install-ssh-hardening.sh"
grep -q 'refusing to enable UFW before SSH migration' "$ROOT/scripts/apply-firewall.sh"
grep -q 'ufw --force reset' "$ROOT/scripts/apply-firewall.sh"
grep -q 'migrate-ssh-port.sh' "$ROOT/deploy/deploy.sh"
grep -q 'Port 22' "$ROOT/scripts/migrate-ssh-port.sh"
bash -n "$ROOT/scripts/migrate-ssh-port.sh"
bash -n "$ROOT/scripts/apply-firewall.sh"
bash -n "$ROOT/scripts/install-ssh-hardening.sh"
bash -n "$ROOT/scripts/configure-tailscale-exit-node.sh"
printf '%s\n' 'test-security-policy: passed'
 <<< "$firewall"
grep -q '^ufw allow 22/tcp
grep -q '^ufw default deny incoming$' <<< "$firewall"
grep -q '^ufw default allow outgoing$' <<< "$firewall"
grep -q '^ufw --force enable$' <<< "$firewall"
tailscale=$(DRY_RUN=1 bash "$ROOT/scripts/configure-tailscale-exit-node.sh")
grep -q 'forwarding' <<< "$tailscale"
grep -q 'tailscale0' <<< "$tailscale"
grep -q 'SSH_ADMIN_LOGIN_VERIFIED' "$ROOT/scripts/install-ssh-hardening.sh"
grep -q 'restoring previous SSH configuration' "$ROOT/scripts/install-ssh-hardening.sh"
grep -q 'refusing to enable UFW before SSH migration' "$ROOT/scripts/apply-firewall.sh"
! grep -q 'ufw --force reset' "$ROOT/scripts/apply-firewall.sh"
bash -n "$ROOT/scripts/apply-firewall.sh"
bash -n "$ROOT/scripts/install-ssh-hardening.sh"
bash -n "$ROOT/scripts/configure-tailscale-exit-node.sh"
printf '%s\n' 'test-security-policy: passed'
 <<< "$firewall"
migration_firewall=$(DRY_RUN=1 RESET_UFW=0 POLICY_FILE="$ROOT/config/firewall/policy.env.example" bash "$ROOT/scripts/apply-firewall.sh")
! grep -q 'ufw --force reset' <<< "$migration_firewall"
grep -q '^ufw allow 22/tcp
grep -q '^ufw default deny incoming$' <<< "$firewall"
grep -q '^ufw default allow outgoing$' <<< "$firewall"
grep -q '^ufw --force enable$' <<< "$firewall"
tailscale=$(DRY_RUN=1 bash "$ROOT/scripts/configure-tailscale-exit-node.sh")
grep -q 'forwarding' <<< "$tailscale"
grep -q 'tailscale0' <<< "$tailscale"
grep -q 'SSH_ADMIN_LOGIN_VERIFIED' "$ROOT/scripts/install-ssh-hardening.sh"
grep -q 'restoring previous SSH configuration' "$ROOT/scripts/install-ssh-hardening.sh"
grep -q 'refusing to enable UFW before SSH migration' "$ROOT/scripts/apply-firewall.sh"
! grep -q 'ufw --force reset' "$ROOT/scripts/apply-firewall.sh"
bash -n "$ROOT/scripts/apply-firewall.sh"
bash -n "$ROOT/scripts/install-ssh-hardening.sh"
bash -n "$ROOT/scripts/configure-tailscale-exit-node.sh"
printf '%s\n' 'test-security-policy: passed'
 <<< "$migration_firewall"
grep -q '^ufw default deny incoming$' <<< "$firewall"
grep -q '^ufw default allow outgoing$' <<< "$firewall"
grep -q '^ufw --force enable$' <<< "$firewall"
tailscale=$(DRY_RUN=1 bash "$ROOT/scripts/configure-tailscale-exit-node.sh")
grep -q 'forwarding' <<< "$tailscale"
grep -q 'tailscale0' <<< "$tailscale"
grep -q 'SSH_ADMIN_LOGIN_VERIFIED' "$ROOT/scripts/install-ssh-hardening.sh"
grep -q 'restoring previous SSH configuration' "$ROOT/scripts/install-ssh-hardening.sh"
grep -q 'refusing to enable UFW before SSH migration' "$ROOT/scripts/apply-firewall.sh"
! grep -q 'ufw --force reset' "$ROOT/scripts/apply-firewall.sh"
bash -n "$ROOT/scripts/apply-firewall.sh"
bash -n "$ROOT/scripts/install-ssh-hardening.sh"
bash -n "$ROOT/scripts/configure-tailscale-exit-node.sh"
printf '%s\n' 'test-security-policy: passed'
