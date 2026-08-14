#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
command -v docker >/dev/null 2>&1 || { printf 'container-test: docker not available\n' >&2; exit 2; }

# The repository is copied into the disposable container. Test credentials are
# generated only inside the container and are never written to this repository.
docker run --rm -i \
  -v "$ROOT:/source:ro" \
  debian:stable-slim \
  bash -s <<'CONTAINER_SCRIPT'
set -euo pipefail
apt-get update -qq
apt-get install -y -qq bash python3 ca-certificates
cp -a /source /tmp/vps-gateway-infra
cd /tmp/vps-gateway-infra
cat > /tmp/test.env <<'EOF'
VLESS_UUID=00000000-0000-4000-8000-000000000001
REALITY_PRIVATE_KEY=test-reality-private-key
REALITY_SHORT_ID=0000000000000001
SOCKS_USERNAME=test-user
SOCKS_PASSWORD=test-socks-password
CLOUDFLARED_TUNNEL_TOKEN=test-cloudflared-token
SING_BOX_VERSION=1.13.18
CLOUDFLARED_VERSION=2026.8.1
EOF
./deploy/deploy.sh --dry-run --env-file /tmp/test.env >/tmp/deploy-output
! grep -q 'test-reality-private-key\|test-socks-password\|test-cloudflared-token' /tmp/deploy-output
python3 -m json.tool .generated/sing-box/config.json >/dev/null
printf '%s\n' 'container-test: passed'
CONTAINER_SCRIPT
