# Deployment

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

This workflow is explicit and must be run only once for a new gateway. It does
not regenerate credentials during normal deployment.

After the official sing-box binary is installed, generate fresh identity
material:

```sh
sudo ./scripts/install-sing-box.sh
sudo ./scripts/generate-secrets.sh
```

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
