# Deployment

## Primary gateway

On a fresh Debian/Ubuntu VPS, clone the intended development branch and run:

```sh
git clone --branch dev https://github.com/jooya98/vps-gateway-infra.git /opt/vps-gateway-infra
cd /opt/vps-gateway-infra
sudo bash bootstrap.sh
```

The primary gateway profile deploys sing-box and the configured Cloudflare Tunnel path. Review docs/ssh-firewall.md before first deployment: the intended non-root administrator key must be tested in a second SSH session before hardening is allowed to continue.

The firewall is additive and does not reset UFW. SSH is standardized on TCP/22. Root login and password authentication are disabled only after the operator explicitly confirms successful login and sudo access using the administrator key.

## Optional Tailscale exit node

Tailscale exit-node configuration is separate from the sing-box deployment:

```sh
sudo bash ./scripts/configure-tailscale-exit-node.sh
```

See docs/tailscale-exit-node.md. This does not redirect sing-box outbound traffic through Tailscale; it advertises the VPS for clients that explicitly choose it as their Tailscale exit node.

## DNS steering

DNS/SNI steering is not part of the default installation path and is not required for either Tailscale exit node or sing-box gateway. The existing DNS steering files are experimental/optional and should not be treated as an active feature until the installer, firewall, runtime behavior, and tests are brought into agreement.

## Validation

Run the repository checks before deployment:

```sh
./scripts/validate-repository.sh
./tests/test-security-policy.sh
./tests/test-local.sh
```

Runtime network behavior still needs to be verified on the fresh VPS after deployment. A successful shell test is not proof that provider routing, external reachability, or Tailscale tailnet policy is correct.
