# Deployment

## Primary gateway

On a fresh Debian/Ubuntu VPS, clone the intended development branch and run:

```sh
git clone --branch dev https://github.com/jooya98/vps-gateway-infra.git /opt/vps-gateway-infra
cd /opt/vps-gateway-infra
sudo bash bootstrap.sh
```

The primary gateway profile deploys sing-box and the configured Cloudflare Tunnel path. Review docs/ssh-firewall.md before first deployment: the intended non-root administrator key must be tested in a second SSH session before hardening is allowed to continue.

SSH is standardized on TCP/22. Root login and password authentication are disabled only after the operator explicitly confirms successful login and sudo access using the administrator key. After that confirmation, the final gateway firewall stage resets UFW and rebuilds the repository's gateway allow-list, replacing provider-specific rules. On later managed firewall runs, an explicitly configured Tailscale exit node's forwarding rule is also reconstructed from its saved state.

## Optional Tailscale exit node

Tailscale exit-node configuration is separate from the sing-box deployment and must run **after** `bootstrap.sh` succeeds and its initial self-audit passes:

```sh
sudo bash ./scripts/configure-tailscale-exit-node.sh
```

The script requires active UFW, stores the detected WAN interface in `/etc/vps-gateway/tailscale-exit-node.conf`, and creates the forwarding rule. Approve the exit node in the Tailscale admin console, then select it on clients. Later `apply-firewall.sh` resets preserve the intended Tailscale forwarding rule by rebuilding it from the saved state. This does not redirect sing-box outbound traffic through Tailscale; see docs/tailscale-exit-node.md.

## DNS steering

DNS/SNI steering is not part of the default installation path and is not required for either Tailscale exit node or sing-box gateway. The existing DNS steering files are experimental/optional and should not be treated as an active feature until the installer, firewall, runtime behavior, and tests are brought into agreement.

## Validation

Run the repository checks before deployment:

```sh
./scripts/validate-repository.sh
./tests/test-security-policy.sh
./tests/test-gateway-profile.sh
```

Runtime network behavior still needs to be verified on the fresh VPS after deployment. A successful shell test is not proof that provider routing, external reachability, or Tailscale tailnet policy is correct.

## Client artifacts

After deployment, the client generator writes protocol artifacts with restrictive permissions. Run it as root only when you need to regenerate them:

```sh
sudo bash ./scripts/generate-client-profiles.sh
```

The generator must not emit Reality private keys or Cloudflare tunnel tokens into client-facing files.

## Connectivity audit

Use the audit utility against the curated domain inventory:

```sh
./scripts/gateway-connectivity-audit.sh config/gateway/domains/ai-domains.txt
```

For an authenticated local SOCKS path:

```sh
PROXY='socks5h://user:password@127.0.0.1:1080' ./scripts/gateway-connectivity-audit.sh config/gateway/domains/ai-domains.txt
```

The audit distinguishes DNS/TCP/TLS failures from application responses. An HTTP 401, 403, 404, or 429 after successful connection means the network path reached the service, not that the application request succeeded. This audit does not enable or validate the optional DNS/SNI steering path.

## Rollback

Before changing managed gateway state, inspect the backup created by the deployment. The repository includes a rollback helper at deploy/rollback.sh; read its target and backup-selection behavior before invoking it. SSH configuration has a separate root-owned backup under /var/lib/vps-gateway/ssh-backups and is restored automatically when hardening validation or reload fails.
