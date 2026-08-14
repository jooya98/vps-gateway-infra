# Architecture

## Reference artifact model

The deleted VPS is represented only by the preserved archive and its extracted
contents under `reference/`. Those files are immutable forensic input. They are
not runtime configuration and are not restored wholesale.

The snapshot provides configuration intent for sing-box, SSH hardening, UFW,
and the cloudflared systemd unit. It does not provide package installation,
complete systemd state, users, host keys, Docker state, or the cloudflared token.

## Template model

Sanitized templates under `templates/` contain only reproducible structure.
The sing-box template retains the observed VLESS Reality and authenticated
SOCKS topology while replacing credentials with variable placeholders. SSH is a
small managed drop-in, not a copy of the distribution's complete sshd_config.
UFW is represented as a declarative policy rather than raw `/etc/ufw` state.

## Secret injection model

Secrets are supplied through the process environment or an ignored env file.
Required values include the VLESS UUID, Reality private key, SOCKS password, and
Cloudflare tunnel token. The token is written to a protected runtime file by
the deployment process; it is never embedded in Git-tracked templates.

Rendered files live in `.generated/` during validation and are installed only
after validation succeeds. Output and errors avoid printing environment values.

## Deployment flow

```text
preflight -> dependencies -> render -> validate -> install -> enable -> health
```

`deploy/deploy.sh --dry-run` stops after validation and is suitable for local
or container testing. A real run requires explicit root access on Debian.
Installation is intentionally minimal and can be extended without changing the
reference boundary.

## Testing strategy

The first test target is `debian:stable-slim`. The container receives a copy of
the repository and temporary test values. It runs rendering and validation only;
services are not expected to start because a normal disposable container does
not run systemd and does not need real networking.

Tests verify shell syntax, required variables, JSON validity, systemd unit
structure where `systemd-analyze` is available, firewall policy generation, and
absence of known secret values in generated or tracked files.

## Explicit assumptions

- The reference `config.json` is treated as sing-box configuration based on
  its observed schema; the original sing-box unit and installation method were
  not preserved.
- The reference's public SOCKS port is disabled by default in the declarative
  firewall policy until its exposure is explicitly approved.
- Cloudflare tunnel credentials are external inputs because the token file was
  absent from the reference artifact.
