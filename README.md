# VPS Gateway Infrastructure

Reproducible, security-focused Debian gateway provisioning for a single comprehensive gateway profile.

## Install

On a fresh Debian VPS:

```bash
git clone https://github.com/jooya98/vps-gateway-infra.git /opt/vps-gateway-infra
cd /opt/vps-gateway-infra
sudo bash bootstrap.sh
```

`bootstrap.sh` is the only public installation entrypoint. It collects host-specific values interactively, preserves existing credentials when present, installs required software, configures SSH/UFW, provisions the local-managed Cloudflare Tunnel, creates DNS records, obtains the Let's Encrypt certificate through Cloudflare DNS-01, activates the complete sing-box multi-protocol configuration, and generates the client bundle.

No `export`, separate activation command, profile selection, or manual certificate installation is required.

## Interactive inputs

Fresh installations prompt for the values that are genuinely host/account specific:

- SOCKS/HTTP username
- Cloudflare API token
- Cloudflare account ID
- Cloudflare zone
- Tunnel hostname
- Direct TLS hostname
- Cloudflare Tunnel name
- Let's Encrypt email

Generated credentials and operational state stay outside Git under root-owned files.

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
                            Echo

 direct.echo.engine.qzz.io  ---- DNS-only A ----> Echo
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

All development happens on `feat/resilient-gateway`. `master` is reserved for the production release state.

Repository tests live under `tests/`. The intended validation path is:

```bash
./scripts/validate-repository.sh
./tests/test-local.sh
```
