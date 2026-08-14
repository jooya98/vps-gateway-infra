#!/usr/bin/env bash
set -euo pipefail
DRY_RUN=${DRY_RUN:-0}
VERSION=${CLOUDFLARED_VERSION:-latest}
INSTALL_PATH=${CLOUDFLARED_BIN:-/usr/local/bin/cloudflared}
API_BASE=https://api.github.com/repos/cloudflare/cloudflared/releases

case "$(dpkg --print-architecture 2>/dev/null || uname -m)" in
  amd64|x86_64) ARCH=amd64;;
  arm64|aarch64) ARCH=arm64;;
  *) printf 'cloudflared: unsupported architecture\n' >&2; exit 1;;
esac

release_url() {
  if [[ "$VERSION" == latest ]]; then printf '%s/latest\n' "$API_BASE"; else printf '%s/tags/%s\n' "$API_BASE" "${VERSION#v}"; fi
}

if [[ "$DRY_RUN" == 1 ]]; then
  printf 'cloudflared: dry-run architecture=%s version=%s\n' "$ARCH" "$VERSION"
  exit 0
fi
[[ "$(id -u)" == 0 ]] || { printf 'cloudflared: root is required\n' >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { printf 'cloudflared: curl is required\n' >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { printf 'cloudflared: python3 is required\n' >&2; exit 1; }

release_json=$(mktemp)
binary=$(mktemp)
cleanup() { rm -f "$release_json" "$binary"; }
trap cleanup EXIT
curl -fsSL --compressed --retry 3 "$(release_url)" -o "$release_json"
IFS=$'\t' read -r tag asset_url digest asset_name < <(python3 - "$release_json" "$ARCH" <<'PY'
import json, sys
release=json.load(open(sys.argv[1]))
arch=sys.argv[2]
name=f'cloudflared-linux-{arch}'
for asset in release.get('assets',[]):
    if asset['name'] == name:
        print(release['tag_name'], asset['browser_download_url'], asset.get('digest',''), asset['name'], sep='\t')
        break
else:
    raise SystemExit(f'asset not found: {name}')
PY
)
printf '%s\n' "cloudflared: downloading official release $tag ($ARCH)"
if ! curl -fsSL --compressed --connect-timeout 30 --max-time 120 --retry 3 "$asset_url" -o "$binary"; then
  printf '%s\n' "cloudflared: official release asset download failed for $tag ($ARCH); no binary was installed" >&2
  exit 1
fi
if [[ "$digest" == sha256:* ]]; then
  expected=${digest#sha256:}; actual=$(sha256sum "$binary" | awk '{print $1}')
  [[ "$actual" == "$expected" ]] || { printf 'cloudflared: checksum verification failed\n' >&2; exit 1; }
else
  printf '%s\n' 'cloudflared: upstream checksum unavailable; continuing without checksum verification' >&2
fi
install -m 0755 "$binary" "$INSTALL_PATH"
"$INSTALL_PATH" --version >/dev/null
printf '%s\n' "cloudflared: installed and validated $tag"
