# VPS Gateway Infrastructure

Reproducible, security-focused gateway provisioning for a single comprehensive gateway profile.

## Install

On a fresh Debian/Ubuntu VPS:

```bash
git clone --branch dev https://github.com/jooya98/vps-gateway-infra.git /opt/vps-gateway-infra
cd /opt/vps-gateway-infra
sudo bash bootstrap.sh
```

`bootstrap.sh` is the only public installation entrypoint. It collects host-specific values interactively, preserves existing credentials when present, installs required software, configures the gateway-owned SSH/UFW policy, provisions the local-managed Cloudflare Tunnel, creates DNS records, obtains the Let's Encrypt certificate through Cloudflare DNS-01, activates the complete sing-box multi-protocol configuration, generates the client bundle, and runs a final read-only self-audit.

No `export`, separate activation command, profile selection, or manual certificate installation is required.

## Interactive inputs

Fresh installations prompt for the values that are genuinely host/account specific:

- SOCKS/HTTP username
- Admin username
- Initial admin password
- Admin SSH public key
- Cloudflare API token
- Cloudflare account ID
- Cloudflare zone
- Tunnel hostname
- Direct TLS hostname
- Cloudflare Tunnel name
- Let's Encrypt email

SSH is standardized on TCP/22. Before hardening, bootstrap requires a second SSH session to verify login with the new administrator key and successful sudo access. The hardening script backs up the existing OpenSSH configuration, moves provider-generated SSH fragments out of the active path, validates the effective policy, and restores the backup if validation or reload fails. The SSH migration first backs up and replaces provider SSH settings to move the listener to TCP/22, temporarily retaining root/password access until the new admin key is verified. After SSH hardening, UFW is reset and rebuilt from the repository allow-list, intentionally replacing provider-specific firewall rules. See `docs/ssh-firewall.md`.

Generated credentials and operational state stay outside Git under root-owned files.

## Final self-audit

After deployment, `bootstrap.sh` automatically runs:

```bash
sudo bash ./scripts/self-audit.sh
```

The audit is read-only. It checks the effective SSH policy, admin account and SSH key ownership/permissions, sudoers permissions, UFW state and expected ingress rules, public and loopback listeners, sing-box and Cloudflare Tunnel service health, native configuration validation, TLS material, Cloudflare state/credential permissions, and DNS resolution of the configured hostnames. If Tailscale exit-node state has been recorded, it also checks IP forwarding, the UFW forwarding rule and Tailscale backend health. It exits non-zero when a required check fails.

One non-blocking security advisory is currently expected: the sing-box systemd unit does not yet declare a dedicated `User=` and therefore runs as root. This is reported as a warning rather than a deployment failure because changing it safely requires coordinated ownership of TLS private keys and other runtime files.

## Independent network capabilities

Tailscale exit-node mode is optional and separate from the sing-box gateway. **Run it only after `bootstrap.sh` and the initial self-audit succeed**:

```bash
sudo bash ./scripts/configure-tailscale-exit-node.sh
```

This installs Tailscale if needed, enables IPv4/IPv6 forwarding, records the WAN interface in `/etc/vps-gateway/tailscale-exit-node.conf`, adds the UFW forwarding rule and advertises the VPS as an exit node. Approve the exit node in the Tailscale admin console, then select it explicitly on clients. It does not route sing-box outbound traffic through Tailscale. When a later managed gateway firewall run resets UFW, `apply-firewall.sh` restores this forwarding rule from the recorded state. See `docs/tailscale-exit-node.md`. DNS/SNI steering is not in the default install path and remains optional pending end-to-end validation.

## Network model

```text
                         Cloudflare
                              |
                    echo.engine.qzz.io
                              |
                       Tunnel / HTTPS
                     /       |       \
              VLESS-WS   VMess-WS   HTTPUpgrade
                              |
                            Gateway

 direct.echo.engine.qzz.io  ---- DNS-only A ----> Gateway
                              |
                 TLS / QUIC direct transports
```

The Cloudflare hostname is proxied through the Tunnel. The direct hostname is intentionally DNS-only because raw TCP/UDP transports are not carried by the standard HTTP ingress path.

## Client bundle

After installation, the complete bundle is generated under:

```text
/home/<client-user>/vpn-client
```

It contains individual protocol files plus:

```text
all-import-links.txt
v2rayn-import.txt
v2rayn-import-base64.txt
README.txt
summary.txt
```

## Safety and idempotency

Runtime credentials are generated once and are not silently rotated. Existing gateway credentials are preserved. Existing Cloudflare Tunnel state is reused when it is compatible with the configured account and tunnel name. Existing DNS records are validated and conflicting records fail closed rather than being overwritten.

Managed sing-box configuration changes are backed up before activation and automatically rolled back if the new configuration fails to start.

## Development

`master` is the production baseline. Development changes are made on dedicated branches and merged into `master` only after validation.

Repository tests live under `tests/`. The intended validation path includes:

```bash
./scripts/validate-repository.sh
./tests/test-security-policy.sh
./tests/test-gateway-profile.sh
```
