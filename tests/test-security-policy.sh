#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

firewall=$(DRY_RUN=1 RESET_UFW=1 POLICY_FILE="$ROOT/config/firewall/policy.env.example" bash "$ROOT/scripts/apply-firewall.sh")
grep -q '^ufw --force reset$' <<< "$firewall"
grep -q '^ufw allow 22/tcp$' <<< "$firewall"
grep -q '^ufw default deny incoming$' <<< "$firewall"
grep -q '^ufw default allow outgoing$' <<< "$firewall"
grep -q '^ufw --force enable$' <<< "$firewall"

migration_firewall=$(DRY_RUN=1 RESET_UFW=0 POLICY_FILE="$ROOT/config/firewall/policy.env.example" bash "$ROOT/scripts/apply-firewall.sh")
! grep -q 'ufw --force reset' <<< "$migration_firewall"
grep -q '^ufw allow 22/tcp
tailscale=$(DRY_RUN=1 bash "$ROOT/scripts/configure-tailscale-exit-node.sh")
grep -q 'forwarding' <<< "$tailscale"
grep -q 'tailscale0' <<< "$tailscale"
grep -q 'SSH_ADMIN_LOGIN_VERIFIED' "$ROOT/scripts/install-ssh-hardening.sh"
grep -q 'restoring previous SSH configuration' "$ROOT/scripts/install-ssh-hardening.sh"
grep -q 'refusing to enable UFW before SSH migration' "$ROOT/scripts/apply-firewall.sh"
grep -q 'ufw --force reset' "$ROOT/scripts/apply-firewall.sh"
grep -q 'migrate-ssh-port.sh' "$ROOT/deploy/deploy.sh"
grep -q 'Port 22' "$ROOT/scripts/migrate-ssh-port.sh"
grep -Fq 'sudoers="/etc/sudoers.d/$ADMIN_USER"' "$ROOT/scripts/create-admin-user.sh"
grep -Fq 'visudo -c >/dev/null' "$ROOT/scripts/create-admin-user.sh"
grep -Fq 'SUDOERS_FILE="/etc/sudoers.d/$ADMIN_USER"' "$ROOT/scripts/self-audit.sh"
grep -Fq '2. Run: sudo -k && sudo -n id -u' "$ROOT/deploy/deploy.sh"
! grep -Fq 'sudo -v && sudo id -u' "$ROOT/deploy/deploy.sh"
bash -n "$ROOT/scripts/create-admin-user.sh"
bash -n "$ROOT/scripts/self-audit.sh"
bash -n "$ROOT/scripts/migrate-ssh-port.sh"
bash -n "$ROOT/scripts/apply-firewall.sh"
bash -n "$ROOT/scripts/install-ssh-hardening.sh"
bash -n "$ROOT/scripts/configure-tailscale-exit-node.sh"
printf '%s\n' 'test-security-policy: passed'
 <<< "$migration_firewall"

# Regression: UFW reports incoming/outgoing defaults together on one line.
ufw_defaults_sample='Default: deny (incoming), allow (outgoing), disabled (routed)'
grep -Eq '^Default: deny [(]incoming[)]' <<< "$ufw_defaults_sample"
grep -Eq '^Default: .*allow [(]outgoing[)]' <<< "$ufw_defaults_sample"
grep -Fq 'Default: .*allow [(]outgoing[)]' "$ROOT/scripts/self-audit.sh"

tailscale=$(DRY_RUN=1 bash "$ROOT/scripts/configure-tailscale-exit-node.sh")
grep -q 'forwarding' <<< "$tailscale"
grep -q 'tailscale0' <<< "$tailscale"
grep -q 'SSH_ADMIN_LOGIN_VERIFIED' "$ROOT/scripts/install-ssh-hardening.sh"
grep -q 'restoring previous SSH configuration' "$ROOT/scripts/install-ssh-hardening.sh"
grep -q 'refusing to enable UFW before SSH migration' "$ROOT/scripts/apply-firewall.sh"
grep -q 'ufw --force reset' "$ROOT/scripts/apply-firewall.sh"
grep -q 'migrate-ssh-port.sh' "$ROOT/deploy/deploy.sh"
grep -q 'Port 22' "$ROOT/scripts/migrate-ssh-port.sh"
grep -Fq 'sudoers="/etc/sudoers.d/$ADMIN_USER"' "$ROOT/scripts/create-admin-user.sh"
grep -Fq 'visudo -c >/dev/null' "$ROOT/scripts/create-admin-user.sh"
grep -Fq 'SUDOERS_FILE="/etc/sudoers.d/$ADMIN_USER"' "$ROOT/scripts/self-audit.sh"
grep -Fq '2. Run: sudo -k && sudo -n id -u' "$ROOT/deploy/deploy.sh"
! grep -Fq 'sudo -v && sudo id -u' "$ROOT/deploy/deploy.sh"
bash -n "$ROOT/scripts/create-admin-user.sh"
bash -n "$ROOT/scripts/self-audit.sh"
bash -n "$ROOT/scripts/migrate-ssh-port.sh"
bash -n "$ROOT/scripts/apply-firewall.sh"
bash -n "$ROOT/scripts/install-ssh-hardening.sh"
bash -n "$ROOT/scripts/configure-tailscale-exit-node.sh"
printf '%s\n' 'test-security-policy: passed'
