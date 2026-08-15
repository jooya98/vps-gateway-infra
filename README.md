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

```

Fresh Debian VPS

```
    |
    v
```

bootstrap
(base packages)

```
    |
    v
```

SSH hardening
(disable unsafe access methods)

```
    |
    v
```

Admin user provisioning
(non-root administrative access)

```
    |
    v
```

Firewall configuration

```
    |
    v
```

Service deployment

```
    |
    v
```

Validation

````

---

# Security Model

## Root access

The initial VPS provider root account is used only for bootstrap operations.

After SSH hardening:

- root SSH login is disabled
- password authentication is disabled
- public key authentication is required

Administrative operations are performed through a dedicated non-root user.

---

## Admin user provisioning

Admin user creation is intentionally separate from SSH hardening.

Run:

```bash
sudo ./scripts/create-admin-user.sh
````

The script:

* creates a dedicated administrative user
* configures `/home/<user>`
* copies the authorized SSH key
* enables sudo access
* creates passwordless sudo rules
* validates sudoers syntax

Example:

```
root
 |
 |  bootstrap only
 |
 v

admin-user
 |
 +-- SSH key authentication
 |
 +-- sudo privileges
```

The user password exists only as a recovery/console mechanism.
SSH password authentication remains disabled.

---

# Safety Boundary

## `reference/`

`reference/` contains forensic input extracted from the original gateway artifact.

It must be treated as immutable.

Do not:

* edit files in place
* deploy directly from this directory
* copy credentials from this directory

Runtime configuration is generated from sanitized templates.

---

# Repository Layout

```
.
├── bootstrap/
│   └── Base Debian package layer
│
├── config/
│   ├── defaults
│   ├── versions
│   ├── profiles
│   └── firewall policy
│
├── deploy/
│   ├── render
│   ├── deploy
│   ├── validate
│   └── rollback
│
├── scripts/
│   ├── create-admin-user.sh
│   ├── install-sing-box.sh
│   ├── install-cloudflared.sh
│   ├── install-ssh-hardening.sh
│   ├── apply-firewall.sh
│   └── validation helpers
│
├── templates/
│   ├── ssh
│   ├── sing-box
│   └── cloudflared
│
├── tests/
│
└── docs/
```

---

# Initial Setup

Clone the repository:

```bash
git clone https://github.com/jooya98/vps-gateway-infra.git \
    /opt/vps-gateway-infra

cd /opt/vps-gateway-infra
```

---

# Bootstrap

Install base packages:

```bash
cp config/packages.env.example config/packages.env

sudo ./bootstrap/01-base-packages.sh
```

The bootstrap layer does **not**:

* create users
* modify SSH configuration
* configure firewall
* install services

Those operations are explicit.

---

# Administrative Access
During gateway bootstrap, the operator is prompted to create an administrative user. The operation can also be executed manually using scripts/create-admin-user.sh.

Validate:

```bash
id <username>

groups <username>

sudo -l -U <username>
```

Test SSH access before closing the root session.

---

# Deployment

Prepare runtime configuration:

```bash
cp .env.example .env
```

Fill required values locally.

Never commit:

```
.env
*.key
*.pem
credentials
tokens
```

---

Dry-run deployment:

```bash
./deploy/deploy.sh \
    --dry-run \
    --env-file .env
```

Real deployment:

```bash
sudo ./deploy/deploy.sh \
    --profile gateway-minimal \
    --env-file /root/vps-gateway-runtime.conf
```

---

# Validation

The project provides validation steps before and after deployment.

Examples:

```bash
sudo ./deploy/validate.sh
```

Checks include:

* rendered configuration validity
* service configuration
* firewall state
* secret leakage prevention
* deployment assumptions

---

# Profiles

Available:

```
default
gateway-minimal
```

Current focus:

```
gateway-minimal
```

Future profiles may include:

* Docker workloads
* monitoring stack
* additional gateway services

---

# Development Workflow

Recommended workflow:

```
change
 |
 v
local validation
 |
 v
test environment
 |
 v
commit
 |
v
release tag
```

Avoid making manual production-only changes.

If a production change is required, convert it into:

* a script change
* a template change
* a validation rule
* documentation

---

# Roadmap

## Completed

* [x] Repository reconstruction from reference artifact
* [x] Template-based configuration generation
* [x] Secret separation
* [x] Debian bootstrap layer
* [x] SSH hardening
* [x] Firewall automation
* [x] Admin user provisioning
* [x] Passwordless sudo
* [x] Validation scripts

## Planned

* [ ] Automated CI validation
* [ ] Release tagging
* [ ] Multi-node gateway support
* [ ] Better observability
* [ ] Automated recovery workflows

---

# Philosophy

A VPS should not depend on the memory of the person who configured it.

Infrastructure becomes reliable when:

```
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

This repository is an attempt to move from manually maintained servers toward
reproducible infrastructure.
