#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
POLICY_FILE="$ROOT/config/firewall/policy.env.example"

firewall=$(DRY_RUN=1 RESET_UFW=1 POLICY_FILE="$POLICY_FILE" bash "$ROOT/scripts/apply-firewall.sh")
grep -q '^ufw --force reset$' <<< "$firewall"
grep -q '^ufw allow 22/tcp$' <<< "$firewall"
grep -q '^ufw allow 1080/tcp$' <<< "$firewall"
grep -q '^ufw allow 8080/tcp$' <<< "$firewall"
grep -q '^ufw default deny incoming$' <<< "$firewall"
grep -q '^ufw default allow outgoing$' <<< "$firewall"
grep -q '^ufw --force enable$' <<< "$firewall"
! grep -q '^ufw route allow in on tailscale0 ' <<< "$firewall"

migration_firewall=$(DRY_RUN=1 RESET_UFW=0 POLICY_FILE="$POLICY_FILE" bash "$ROOT/scripts/apply-firewall.sh")
! grep -q 'ufw --force reset' <<< "$migration_firewall"
grep -q '^ufw allow 22/tcp$' <<< "$migration_firewall"

# Once Tailscale is explicitly configured, a managed UFW reset must restore
# its forwarding rule from the durable, root-owned state file.
printf 'WAN_IF=ens3\n' > "$TMP_DIR/tailscale-exit-node.conf"
tailscale_firewall=$(DRY_RUN=1 RESET_UFW=1 POLICY_FILE="$POLICY_FILE" TAILSCALE_EXIT_NODE_STATE_FILE="$TMP_DIR/tailscale-exit-node.conf" bash "$ROOT/scripts/apply-firewall.sh")
grep -q '^ufw --force reset$' <<< "$tailscale_firewall"
grep -q '^ufw route allow in on tailscale0 out on ens3$' <<< "$tailscale_firewall"
[[ "$(grep -n '^ufw --force reset$' <<< "$tailscale_firewall" | cut -d: -f1)" -lt "$(grep -n '^ufw route allow in on tailscale0 out on ens3$' <<< "$tailscale_firewall" | cut -d: -f1)" ]]

# Invalid persisted interface names must fail closed rather than enter a command.
printf 'WAN_IF=eth0;touch\n' > "$TMP_DIR/invalid-tailscale.conf"
if DRY_RUN=1 POLICY_FILE="$POLICY_FILE" TAILSCALE_EXIT_NODE_STATE_FILE="$TMP_DIR/invalid-tailscale.conf" bash "$ROOT/scripts/apply-firewall.sh" >/dev/null 2>&1; then
  printf '%s\n' 'test-security-policy: invalid Tailscale WAN interface was accepted' >&2
  exit 1
fi

# Regression: UFW reports incoming/outgoing defaults together on one line.
ufw_defaults_sample='Default: deny (incoming), allow (outgoing), disabled (routed)'
grep -Eq '^Default: deny [(]incoming[)]' <<< "$ufw_defaults_sample"
grep -Eq '^Default: .*allow [(]outgoing[)]' <<< "$ufw_defaults_sample"
grep -Fq 'Default: .*allow [(]outgoing[)]' "$ROOT/scripts/self-audit.sh"

tailscale=$(DRY_RUN=1 bash "$ROOT/scripts/configure-tailscale-exit-node.sh")
grep -q 'forwarding' <<< "$tailscale"
grep -q 'tailscale0' <<< "$tailscale"
grep -q 'TAILSCALE_EXIT_NODE_STATE_FILE' "$ROOT/scripts/configure-tailscale-exit-node.sh"
grep -q 'UFW must be active' "$ROOT/scripts/configure-tailscale-exit-node.sh"
grep -q 'TAILSCALE_EXIT_NODE_STATE_FILE' "$ROOT/scripts/apply-firewall.sh"
grep -q 'Tailscale forwarding' "$ROOT/scripts/self-audit.sh"

grep -q 'SSH_ADMIN_LOGIN_VERIFIED' "$ROOT/scripts/install-ssh-hardening.sh"
grep -q 'restoring previous SSH configuration' "$ROOT/scripts/install-ssh-hardening.sh"
grep -q 'refusing to enable UFW before SSH migration' "$ROOT/scripts/apply-firewall.sh"
grep -q 'ufw --force reset' "$ROOT/scripts/apply-firewall.sh"
grep -q 'migrate-ssh-port.sh' "$ROOT/deploy/deploy.sh"
grep -q 'Port 22' "$ROOT/scripts/migrate-ssh-port.sh"
grep -Fq 'sudoers="/etc/sudoers.d/$ADMIN_USER"' "$ROOT/scripts/create-admin-user.sh"
grep -Fq 'visudo -c >/dev/null' "$ROOT/scripts/create-admin-user.sh"
grep -Fq 'SUDOERS_FILE="/etc/sudoers.d/$ADMIN_USER"' "$ROOT/scripts/self-audit.sh"
grep -Fq 'expect_tcp_public' "$ROOT/scripts/self-audit.sh"
grep -q '^SOCKS_ALLOW_FROM=any$' "$ROOT/config/profiles/gateway.env.example"
grep -Fq '2. Run: sudo -k && sudo -n id -u' "$ROOT/deploy/deploy.sh"
! grep -Fq 'sudo -v && sudo id -u' "$ROOT/deploy/deploy.sh"

bash -n "$ROOT/scripts/create-admin-user.sh"
bash -n "$ROOT/scripts/self-audit.sh"
bash -n "$ROOT/scripts/migrate-ssh-port.sh"
bash -n "$ROOT/scripts/apply-firewall.sh"
bash -n "$ROOT/scripts/install-ssh-hardening.sh"
bash -n "$ROOT/scripts/configure-tailscale-exit-node.sh"
printf '%s\n' 'test-security-policy: passed'
