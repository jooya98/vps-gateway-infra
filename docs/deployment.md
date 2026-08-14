# Deployment

## Recommended fresh-VPS flow

On a fresh Debian VPS, clone the public repository and run the single-command
bootstrap as root:

```sh
git clone https://github.com/jooya98/vps-gateway-infra.git /opt/vps-gateway-infra
cd /opt/vps-gateway-infra
sudo ./bootstrap.sh --profile gateway-minimal
```

The bootstrap entrypoint:

1. verifies Debian and required repository files
2. installs only the pre-generation prerequisites when the local base package profile is absent
3. installs the official sing-box binary if it is not already present
4. generates new gateway credentials only when the runtime file is absent
5. prompts once for the Cloudflare tunnel token with hidden input
6. validates the protected runtime and client-information files
7. delegates the actual deployment to `deploy/deploy.sh`
8. prints deployment and service status without printing secrets

The generated files are outside the repository:

```text
/root/vps-gateway-runtime.conf
/root/vps-gateway-client-info.txt
```

The bootstrap script refuses to overwrite an existing runtime file. This makes
re-running it safe for an existing gateway, provided the runtime file remains
valid. It never generates a Cloudflare token.

Review `/root/vps-gateway-client-info.txt` after bootstrap to configure clients.
It contains no Reality private key, SOCKS password, or Cloudflare token.

## Exact rebuild flow

```text
clean Debian VPS
  -> clone private repository
  -> provide .env and secret values out-of-band
  -> optionally provide config/versions.env with pinned releases
  -> run deploy/deploy.sh
  -> install official sing-box and cloudflared binaries
  -> render templates locally on the target
  -> validate JSON, units, and managed policy
  -> create a backup of current managed state
  -> install managed configuration and systemd units
  -> apply firewall policy
  -> enable services
  -> run health checks
```

The normal command is:

```sh
./deploy/deploy.sh --profile gateway-minimal --env-file /path/to/runtime.env
```

`--dry-run` performs preflight, version selection, rendering, validation, and
policy generation without installing binaries or changing systemd/firewall
state. The container test uses this mode after separately exercising the real
upstream binary installers with disposable test paths.

## Secrets

Runtime secrets are supplied through an ignored environment file. They are not
printed, committed, or placed in generated repository files. The Cloudflare
token is written only to `/etc/cloudflared/token` with mode `0600`.

## First deployment on a new gateway

The recommended path for a new VPS is the top-level bootstrap command:

```sh
./bootstrap.sh --profile gateway-minimal
```

It installs the official sing-box binary before generating fresh credentials,
creates the protected runtime file, requests the Cloudflare token interactively,
validates the result, and then executes the normal deployment flow. Review
`/root/vps-gateway-client-info.txt` after completion.

The advanced/manual sequence below remains available when each stage must be
run separately.


The script writes:

```text
/root/vps-gateway-runtime.conf
/root/vps-gateway-client-info.txt
```

The runtime file is mode `0600`, owned by `root:root`, and contains the new
VLESS UUID, Reality private key, Reality short ID, and SOCKS credentials. The
client info file contains only client-facing values and never contains the
Reality private key.

Review the client info:

```sh
less /root/vps-gateway-client-info.txt
```

Add `CLOUDFLARED_TUNNEL_TOKEN` manually to the runtime file. The generator does
not create this value. Validate the completed file:

```sh
./scripts/validate-secrets.sh
```

Deploy:

```sh
./deploy/deploy.sh \\
  --profile gateway-minimal \\
  --env-file /root/vps-gateway-runtime.conf
```

The generator refuses to overwrite existing runtime or client-info files. If
the runtime file already exists, do not run the generator again unless you
intend to rotate credentials and update every client.

## Version policy

`latest` is supported for development but is not reproducible. Production runs
warn when either version is `latest`. For production, copy
`config/versions.env.example` to the ignored `config/versions.env` and replace
both placeholders with tested upstream release versions.

## Rollback safety

Before a real deployment changes managed configuration, systemd units, or UFW
state, `deploy/backup.sh create` saves only the managed files under:

```text
/var/backups/vps-gateway-infra/<UTC timestamp>/
```

This may include the existing Cloudflare token, but the backup is host-local,
mode `0700`, and never part of Git. It does not copy all of `/etc`.

To restore the newest backup:

```sh
sudo ./deploy/rollback.sh
```

Or select an explicit backup directory:

```sh
sudo ./deploy/rollback.sh /var/backups/vps-gateway-infra/<timestamp>
```

Rollback covers managed sing-box/cloudflared configuration and units plus UFW
user rules. It does not restore binaries, unrelated packages, users, host keys,
or the full filesystem.
