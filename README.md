# VPS Gateway Infrastructure

Reproducible, security-focused gateway provisioning for a single comprehensive gateway profile.

## Install

On a fresh Debian/Ubuntu VPS:

```bash
git clone https://github.com/jooya98/vps-gateway-infra.git /opt/vps-gateway-infra
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

The gateway owns the OpenSSH server configuration. Provider-generated `sshd_config.d` fragments are removed from the active configuration and preserved only in a root-controlled backup area for forensics. SSH is standardized on TCP/22, root login is disabled, and password authentication is disabled only after the admin public key has been installed and the SSH policy has been validated.

Generated credentials and operational state stay outside Git under root-owned files.

## Final self-audit

After deployment, `bootstrap.sh` automatically runs:

```bash
sudo bash ./scripts/self-audit.sh
```

The audit is read-only. It checks the effective SSH policy, admin account and SSH key ownership/permissions, sudoers permissions, UFW state and expected ingress rules, public and loopback listeners, sing-box and Cloudflare Tunnel service health, native configuration validation, TLS material, Cloudflare state/credential permissions, and DNS resolution of the configured hostnames. It exits non-zero when a required check fails.

One non-blocking security advisory is currently expected: the sing-box systemd unit does not yet declare a dedicated `User=` and therefore runs as root. This is reported as a warning rather than a deployment failure because changing it safely requires coordinated ownership of TLS private keys and other runtime files.

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
./tests/test-local.sh
```
