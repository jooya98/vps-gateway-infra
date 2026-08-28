# VPS Gateway Infrastructure

Minimal, reproducible, and security-focused Debian gateway provisioning framework.

This project turns a manually configured VPS gateway into a reproducible infrastructure
deployment pipeline.

The goal is not to provide a generic server installer. The goal is to create a
controlled, auditable, and repeatable gateway environment with explicit security
boundaries.

---

## Design Principles

### Reproducibility

A gateway should be rebuildable from a clean Debian installation without relying on
unknown manual changes.

### Explicit state changes

Installation steps are separated into independent operations:

- base package installation
- administrative access provisioning
- SSH hardening
- firewall configuration
- service deployment
- validation

No hidden "magic" configuration is applied.

### Security boundaries

Secrets, credentials, and runtime state are intentionally separated from the repository.

The repository contains:

- templates
- configuration defaults
- deployment logic
- validation tools

It does not contain:

- private keys
- API tokens
- generated credentials
- runtime `.env` files

---

# Lifecycle

A new gateway follows this lifecycle:

```text
Fresh Debian VPS
    |
    v
bootstrap (base packages)
    |
    v
SSH hardening
    |
    v
Admin user provisioning
    |
    v
Firewall configuration
    |
    v
Service deployment
    |
    v
Validation
```

---

# Security Model

## Root access

The initial VPS provider root account is used only for bootstrap operations.

After SSH hardening:

- root SSH login is disabled
- password authentication is disabled
- public key authentication is required

Administrative operations are performed through a dedicated non-root user.

## Admin user provisioning

Admin user creation is intentionally separate from SSH hardening.

Run:

```bash
sudo ./scripts/create-admin-user.sh
```

The script creates a dedicated administrative user, configures its home directory,
copies the authorized SSH key, enables sudo access, creates passwordless sudo rules,
and validates sudoers syntax.

---

# Safety Boundary

## `reference/`

`reference/` contains forensic input extracted from the original gateway artifact.

It must be treated as immutable. Do not edit it, deploy directly from it, or copy
credentials from it. Runtime configuration is generated from sanitized templates.

---

# Repository Layout

```text
.
├── bootstrap/
├── config/
│   ├── defaults
│   ├── versions
│   ├── profiles
│   ├── firewall policy
│   └── gateway/domain inventory
├── deploy/
├── scripts/
├── templates/
├── tests/
└── docs/
```

---

# Initial Setup

```bash
git clone https://github.com/jooya98/vps-gateway-infra.git /opt/vps-gateway-infra
cd /opt/vps-gateway-infra
```

# Bootstrap

```bash
cp config/packages.env.example config/packages.env
sudo ./bootstrap/01-base-packages.sh
```

The bootstrap layer does not create users, modify SSH configuration, configure the
firewall, or install services. Those operations remain explicit.

---

# Deployment

Prepare an ignored runtime file:

```bash
cp .env.example .env
```

Never commit `.env`, private keys, certificates, credentials, or tokens.

Dry-run:

```bash
./deploy/deploy.sh --dry-run --profile gateway-minimal --env-file .env
```

Minimal gateway:

```bash
sudo ./deploy/deploy.sh --profile gateway-minimal --env-file /root/vps-gateway-runtime.conf
```

The resilient profile is deliberately explicit:

```bash
sudo ./deploy/deploy.sh --profile gateway-resilient --env-file /root/vps-gateway-runtime.conf
```

---

# Profiles

`default` and `gateway-minimal` keep the public surface conservative. They retain
VLESS on port 443 and an authenticated SOCKS listener on loopback.

`gateway-resilient` enables VLESS + Shadowsocks + local SOCKS and the optional
private DNS/SNI steering component. Because ordinary HTTPS DNS steering must receive
connections on port 443, this profile moves VLESS to 8443 and uses 443 for sniproxy.

VMess, Trojan, Hysteria2, and TUIC are individually configurable but disabled by
default. TLS transports require an operator-supplied certificate/key pair.

---

# Private DNS Steering

The resilient profile uses `mosajjal/sniproxy` as a small embedded DNS + TLS SNI
proxy. The repository pins sniproxy 2.4.1 and keeps its domain inventory under:

```text
config/gateway/domains/ai-domains.txt
```

The flow is:

```text
client DNS query
    |
    v
private sniproxy DNS
    |
    +-- selected domain --> VPS address --> HTTPS :443 --> SNI relay --> destination
    |
    `-- normal domain ----> upstream DNS --> normal destination
```

This is selective traffic steering, not a universal VPN or a guarantee of access
to every service. DNS cannot by itself overcome transport blocking, account policy,
application authentication, or provider-side regional restrictions.

DNS access is source-CIDR restricted and ends with reject-all rules. It is not an
unrestricted public recursive resolver.

Broad shared domains such as `google.com`, `microsoft.com`, and `cloudflare.com` are
not included merely because an AI provider uses them; only concrete service endpoints
belong in the inventory.

---

# Multi-Transport Gateway

The following flags are independent:

```text
ENABLE_VLESS
ENABLE_SHADOWSOCKS
ENABLE_VMESS
ENABLE_TROJAN
ENABLE_HYSTERIA2
ENABLE_TUIC
ENABLE_SOCKS
```

Ports are deliberately assigned rather than opened as a random range. UFW derives
its ingress rules from the enabled components, so disabled transports do not leave
dead public ports.

---

# Cloudflared

Cloudflared is optional. It is not installed, started, or required when
`ENABLE_CLOUDFLARED=false`. A tunnel token is required only when that component is
explicitly enabled.

---

# Client Profiles

The client generator preserves the existing VLESS/v2rayN/Mihomo workflow and adds
artifacts for enabled Shadowsocks, VMess, Trojan, Hysteria2, and TUIC transports.
Generated files are mode `0600`. Reality private keys and tunnel tokens are not
written to client artifacts.

---

# Validation and Audit

Repository validation:

```bash
./scripts/validate-repository.sh
```

Local tests:

```bash
./tests/test-local.sh
./tests/test-resilient.sh
```

Connectivity audit:

```bash
./scripts/gateway-connectivity-audit.sh config/gateway/domains/ai-domains.txt
```

The audit distinguishes DNS, TCP, TLS, and HTTP/application outcomes. A `401`, `403`,
`404`, or `429` after successful DNS/TCP/TLS is evidence that the network path reached
the service; it is not collapsed into a generic network failure.

---

# Rollback Safety

Managed-state backups and rollback remain part of the deployment pipeline. A real
deployment creates the managed-state backup before installing new binaries or
configuration.

---

# Development Workflow

Recommended workflow:

```text
change -> local validation -> disposable test -> commit -> release tag
```

Avoid production-only manual changes. Convert required changes into scripts, templates,
validation rules, or documentation.

---

# Philosophy

A VPS should not depend on the memory of the person who configured it.

Infrastructure becomes reliable when:

```text
knowledge
    |
    v
documentation
    |
    v
automation
    |
    v
repeatable systems
```
