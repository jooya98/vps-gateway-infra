#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
command -v docker >/dev/null 2>&1 || { printf 'container-test: docker not available\n' >&2; exit 2; }

# Use the live Debian mirrors inside the container; the snapshot metadata in
# the image is a reference but is not required for this test to pass.
docker run --rm -i \
  -v "$ROOT:/source:ro" \
  debian:stable-slim \
  bash -s <<'CONTAINER_SCRIPT'
set -euo pipefail
apt-get -o Acquire::Retries=3 -o Acquire::http::Timeout=60 -o Acquire::https::Timeout=60 update -qq
DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=3 -o Acquire::http::Timeout=60 -o Acquire::https::Timeout=60 install -y -qq bash python3 ca-certificates curl tar

cp -a /source /tmp/vps-gateway-infra
cd /tmp/vps-gateway-infra
cat > /tmp/test.env <<'EOF'
VLESS_UUID=00000000-0000-4000-8000-000000000001
REALITY_PRIVATE_KEY=test-reality-private-key
REALITY_SHORT_ID=0000000000000001
SOCKS_USERNAME=test-user
SOCKS_PASSWORD=test-socks-password
CLOUDFLARED_TUNNEL_TOKEN=test-cloudflared-token
SING_BOX_VERSION=v1.13.18
CLOUDFLARED_VERSION=2026.8.1
SING_BOX_BIN=/tmp/sing-box
CLOUDFLARED_BIN=/tmp/cloudflared
EOF

# Exercise the real official download/install paths using disposable paths.
DRY_RUN=0 SING_BOX_VERSION=v1.13.18 SING_BOX_BIN=/tmp/sing-box ./scripts/install-sing-box.sh
DRY_RUN=0 CLOUDFLARED_VERSION=2026.8.1 CLOUDFLARED_BIN=/tmp/cloudflared ./scripts/install-cloudflared.sh
/tmp/sing-box version >/dev/null
/tmp/cloudflared --version >/dev/null

# Exercise the full repository workflow without changing container systemd/UFW.
./deploy/deploy.sh --dry-run --profile gateway-minimal --env-file /tmp/test.env >/tmp/deploy-output
! grep -q 'test-reality-private-key\|test-socks-password\|test-cloudflared-token' /tmp/deploy-output
python3 -m json.tool .generated/sing-box/config.json >/dev/null
grep -q 'PROFILE_NAME=gateway-minimal' config/profiles/gateway-minimal.env.example
printf '%s\n' 'container-test: passed'
CONTAINER_SCRIPT
